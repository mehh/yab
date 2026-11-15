import AppKit
import SwiftUI

// Elements' DOM tree in AppKit, as Network's table is (DevNetTable.swift):
// an NSTableView of the lines DevTree.swift makes, one row a line, drawn as
// Chrome draws them (DOMTreeWidget, domTreeWidget.css): the ⋯ of the
// selected line, 12 points a level, the solid triangle in a box a line tall,
// the tag, attributes and values in their colors, the badges and ⋯ dots,
// `== $0`. A SwiftUI LazyVStack laid out every line above a node brought into
// view, 240 to 345 ms for one 1,700 lines down; the table knows each row's
// place from its height, and only the rows on screen are made.

/// Where things are on a line, Chrome's (DOMTreeWidget computeLeftIndent).
enum DevTreeMetrics {
    /// The ⋯ of the selected line, before the indent.
    static let menu: CGFloat = 14 // design: Chrome's gutter for the selected line's menu
    static let indent: CGFloat = 12
    /// The triangle's box: a line tall, easy to hit.
    static let arrow: CGFloat = 16
    /// The least a line's words wrap in, however deep it is.
    static let room: CGFloat = 260
    static let trailing: CGFloat = 8
    static let line: CGFloat = 16
    static let font = DevMono.nsFont(11, weight: .regular)
    static let italic = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    static let glyph = NSFont.systemFont(ofSize: 11)
    static let advance = ("0" as NSString).size(withAttributes: [.font: font]).width
    static let dots = (" ⋯ " as NSString).size(withAttributes: [.font: font]).width
    static let picked = ("  == $0" as NSString).size(withAttributes: [.font: italic]).width
    static let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font))
    /// The words' first line, in the middle of a line's 16 points.
    static let inset = max(0, floor((line - lineHeight) / 2))
    static func textStart(_ depth: Int) -> CGFloat { menu + CGFloat(depth) * indent + arrow }
    static func contentWidth(_ maxDepth: Int, view: CGFloat) -> CGFloat { max(view, textStart(maxDepth) + room) }
}

struct DevTreeTable: NSViewRepresentable {
    let model: DevWorkbench
    /// The node whose attributes are being edited in its line, and their text.
    let editing: Int?
    let editText: String
    let select: (Int, Bool) -> Void
    let toggle: (DevDOMNode, Bool) -> Void
    let doubleClick: (DevTreeLine) -> Void
    let menu: (DevDOMNode) -> NSMenu
    let follow: (URL) -> Void
    let commit: (Int, String) -> Void
    let cancel: () -> Void
    let hover: (Int) -> Void

    func makeCoordinator() -> DevTreeTableController { DevTreeTableController() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.contentView.drawsBackground = false
        let table = DevTreeTableView()
        table.controller = context.coordinator
        table.headerView = nil
        if table.responds(to: NSSelectorFromString("setStyle:")) { table.style = .plain }
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.intercellSpacing = .zero
        table.gridStyleMask = []
        table.usesAlternatingRowBackgroundColors = false
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsColumnResizing = false
        table.allowsEmptySelection = true
        table.focusRingType = .none
        table.rowSizeStyle = .custom
        table.rowHeight = DevTreeMetrics.line
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("line"))
        column.resizingMask = []
        table.addTableColumn(column)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        // A little room above and below, as Chromium's tree has.
        scroll.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = table
        context.coordinator.table = table
        context.coordinator.scroll = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(DevTreeTableController.scrolled(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(DevTreeTableController.resized(_:)),
                                               name: NSView.frameDidChangeNotification, object: scroll.contentView)
        // Where the tree is in the window, read when a key comes (DevKeys).
        model.treeView = scroll
        ThreadScroller.put(on: scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if model.treeView !== scroll { model.treeView = scroll }
        context.coordinator.update(self)
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: DevTreeTableController) {
        NotificationCenter.default.removeObserver(coordinator)
    }
}

/// The table: it never takes the keyboard (the card's host has it, and the
/// tree's keys are Chrome's, DevKeys), and a press is the tree's own, not
/// NSTableView's selection, which scrolled the row pressed into view.
final class DevTreeTableView: NSTableView {
    weak var controller: DevTreeTableController?
    private var tracking: NSTrackingArea?

    override var acceptsFirstResponder: Bool { false }
    /// Every press is the table's, but in the attributes' editor.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var view: NSView? = hit
        while let at = view, at !== self { if at is NSTextField { return hit }; view = at.superview }
        return self
    }
    override func mouseDown(with event: NSEvent) { controller?.press(event) }
    override func menu(for event: NSEvent) -> NSMenu? { controller?.menu(at: convert(event.locationInWindow, from: nil)) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) { controller?.pointed(convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { controller?.pointed(convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { controller?.pointed(nil) }
}

@MainActor final class DevTreeTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    var parent: DevTreeTable?
    weak var table: DevTreeTableView?
    weak var scroll: NSScrollView?
    private(set) var tree = DevTreeLines([])
    private var made = -1
    /// Each row's height at the column's width, 0 while not measured.
    private var heights: [CGFloat] = []
    private var width: CGFloat = 0
    private var hovered = -1
    /// What the rows were drawn with: the selected line, the line the find
    /// shows and its words, the node being edited, what was open.
    private var picked = (node: 0, close: false)
    private var lit = (node: 0, words: "")
    private var editing: Int?
    private var open: Set<Int> = []
    private var seen = (reveal: -1, key: -1, top: -1)
    /// A row pressed stays where it is, as in Chromium.
    private var pressed = 0
    /// A reveal asked before the table had its size.
    private var waiting: (() -> Void)?
    /// Scrolling to put a kept top row back: that row stays kept.
    private var steering = false

    // MARK: the model in

    func update(_ next: DevTreeTable) {
        parent = next
        guard let table else { return }
        let model = next.model
        let lines = model.treeLines
        let fresh = model.linesMade != made || lines.lines.count != tree.lines.count
        if seen.reveal < 0 { seen = (model.elementsReveal, model.elementsKeyReveal, model.elementsTopReveal) }
        let nowPicked = (model.selectedNode, model.selectedClose)
        let nowLit = model.elementsFind ? (model.elementsMatchNode, model.elementsSearched) : (0, "")
        let selectionMoved = nowPicked != picked
        let startEditing = next.editing != nil && next.editing != editing
        let first = made < 0
        if fresh {
            // Kept where it is when lines come or go above: the line at the
            // top stays at the top, as SwiftUI's scroll position kept it.
            let anchor = topLine()
            made = model.linesMade
            tree = lines
            picked = nowPicked; lit = nowLit; editing = next.editing; open = model.expanded
            fit(reload: false)
            heights = Array(repeating: 0, count: lines.lines.count)
            table.reloadData()
            if let anchor, let row = tree.place[anchor.id] { scrollTo(y: table.rect(ofRow: row).minY + anchor.offset) }
            hovered = -1
            pointedAgain()
        } else {
            var rows = IndexSet()
            func add(_ node: Int, close: Bool) { if node != 0, let row = tree.at(node, close: close) { rows.insert(row) } }
            if selectionMoved { add(picked.node, close: picked.close); add(nowPicked.0, close: nowPicked.1); picked = nowPicked }
            if nowLit != lit { add(lit.node, close: false); add(nowLit.0, close: false); lit = nowLit }
            if next.editing != editing { add(editing ?? 0, close: false); add(next.editing ?? 0, close: false); editing = next.editing }
            if model.expanded != open {
                // What is open changed without the lines changing (a node
                // with nothing to show): only its triangle turns.
                for id in model.expanded.symmetricDifference(open) { add(id, close: false) }
                open = model.expanded
            }
            fit(reload: true)
            reload(rows)
        }
        if startEditing, let field = editField(), let window = table.window {
            window.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
        if first {
            // Shown again (another panel, another tab and back): where it was,
            // else the selected line in view.
            if let top = model.elementsTop, tree.place[top] != nil { later { [weak self] in self?.showTop(top) } }
            else if model.selectedNode != 0 { later { [weak self] in self?.show(model.selectedNode, close: model.selectedClose, least: false) } }
        }
        reveal(model, selectionMoved: selectionMoved)
    }

    private var ready: Bool { (scroll?.contentView.bounds.height ?? 0) > 0 && table?.window != nil }

    /// Now if the table has its size, else once it has it.
    private func later(_ act: @escaping () -> Void) {
        if ready { act(); return }
        waiting = act
        DispatchQueue.main.async { [weak self] in self?.runWaiting() }
    }

    private func runWaiting() {
        guard ready, let waiting else { return }
        self.waiting = nil
        waiting()
    }

    private func reload(_ rows: IndexSet) {
        guard let table, !rows.isEmpty else { return }
        for row in rows where row < heights.count { heights[row] = 0 }
        table.noteHeightOfRows(withIndexesChanged: rows)
        table.reloadData(forRowIndexes: rows, columnIndexes: [0])
    }

    /// The column as wide as the deepest line needs, or the view: the rows'
    /// words wrap in what is left of it.
    private func fit(reload: Bool) {
        guard let table, let clip = scroll?.contentView, let column = table.tableColumns.first else { return }
        let wide = DevTreeMetrics.contentWidth(tree.maxDepth, view: clip.bounds.width)
        guard abs(wide - width) > 0.5 || abs(column.width - wide) > 0.5 else { return }
        width = wide
        column.width = wide
        table.frame.size.width = wide
        guard reload else { return }
        // Every row's room changed: measured again, the rows on screen made again.
        heights = Array(repeating: 0, count: tree.lines.count)
        table.reloadData()
    }

    // MARK: rows

    func numberOfRows(in tableView: NSTableView) -> Int { tree.lines.count }

    private func line(_ row: Int) -> DevTreeLine? { tree.lines.indices.contains(row) ? tree.lines[row] : nil }

    private func isPicked(_ line: DevTreeLine) -> Bool { picked.node == line.node.id && (line.kind == .close) == picked.close }

    private func litWords(_ line: DevTreeLine) -> String? { line.kind != .close && lit.node != 0 && line.node.id == lit.node ? lit.words : nil }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let line = line(row) else { return DevTreeMetrics.line }
        if row < heights.count, heights[row] > 0 { return heights[row] }
        let room = max(40, width - DevTreeMetrics.textStart(line.depth) - DevTreeMetrics.trailing)
        let pickedLine = isPicked(line)
        var height = DevTreeMetrics.line
        // Most lines are a line: counted, not measured (the font's every
        // glyph is as wide); one that may wrap is measured as it is drawn.
        if editing == line.node.id && line.kind != .close {
            height = DevTreeMetrics.line
        } else if let wide = line.plainWidth(picked: pickedLine), wide <= room - 0.5 {
            height = DevTreeMetrics.line
        } else {
            let text = line.attributed(picked: pickedLine, lit: litWords(line))
            let box = text.boundingRect(with: CGSize(width: room, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
            height = max(DevTreeMetrics.line, ceil(box.height) + 2 * DevTreeMetrics.inset)
        }
        if row < heights.count { heights[row] = height }
        return height
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let line = line(row), let model = parent?.model else { return nil }
        let cell = tableView.makeView(withIdentifier: DevTreeCell.id, owner: nil) as? DevTreeCell ?? DevTreeCell()
        let pickedLine = isPicked(line)
        cell.line = line
        cell.picked = pickedLine
        cell.hovered = row == hovered
        cell.expanded = model.expanded.contains(line.node.id)
        cell.room = max(40, width - DevTreeMetrics.textStart(line.depth) - DevTreeMetrics.trailing)
        if editing == line.node.id && line.kind != .close {
            cell.text = nil
            cell.edit(parent?.editText ?? "", delegate: self)
        } else {
            cell.text = line.attributed(picked: pickedLine, lit: litWords(line))
            cell.edit(nil, delegate: self)
        }
        cell.needsDisplay = true
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    private func editField() -> NSTextField? {
        guard let table, let editing, let row = tree.at(editing, close: false), row < table.numberOfRows else { return nil }
        return (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? DevTreeCell)?.field
    }

    // MARK: the attributes' editor

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard let editing else { return false }
        if selector == #selector(NSResponder.insertNewline(_:)) { parent?.commit(editing, control.stringValue); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { parent?.cancel(); return true }
        return false
    }

    // MARK: the hand

    func press(_ event: NSEvent) {
        guard let table, let parent else { return }
        let point = table.convert(event.locationInWindow, from: nil)
        let row = table.row(at: point)
        guard let line = line(row) else { return }
        claimKeys()
        let box = table.rect(ofRow: row)
        let start = DevTreeMetrics.textStart(line.depth)
        let firstLine = point.y < box.minY + DevTreeMetrics.line
        // The selected line's ⋯: its menu, as Chromium's gutter button.
        if isPicked(line), point.x < DevTreeMetrics.menu, firstLine {
            parent.menu(line.node).popUp(positioning: nil, at: NSPoint(x: 0, y: box.minY + DevTreeMetrics.line), in: table)
            return
        }
        // The triangle; ⌥ opens or closes everything under it, as Chromium's.
        if line.arrow, firstLine, point.x >= start - DevTreeMetrics.arrow, point.x < start {
            parent.toggle(line.node, event.modifierFlags.contains(.option))
            return
        }
        if event.clickCount == 2 { parent.doubleClick(line); return }
        if let url = link(at: point, line: line, row: row) { parent.follow(url); return }
        pressed = line.node.id
        parent.select(line.node.id, line.kind == .close)
    }

    /// Out of the attributes' editor, the keys are the tree's again: the
    /// card's host takes them, as a press anywhere in the card does.
    private func claimKeys() {
        guard let table, let window = table.window, window.firstResponder is NSTextView else { return }
        var view = table.superview
        while let at = view, !(at is DevKeyTarget) { view = at.superview }
        if let view { window.makeFirstResponder(view) }
    }

    /// A link of an attribute's value under the point, as the words are laid out.
    private func link(at point: NSPoint, line: DevTreeLine, row: Int) -> URL? {
        guard let table, line.hasLink else { return nil }
        let box = table.rect(ofRow: row)
        let room = max(40, width - DevTreeMetrics.textStart(line.depth) - DevTreeMetrics.trailing)
        let local = NSPoint(x: point.x - DevTreeMetrics.textStart(line.depth), y: point.y - box.minY - DevTreeMetrics.inset)
        guard local.x >= 0, local.y >= 0 else { return nil }
        let text = line.attributed(picked: isPicked(line), lit: nil)
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: room, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        var fraction: CGFloat = 0
        let glyph = layout.glyphIndex(for: local, in: container, fractionOfDistanceThroughGlyph: &fraction)
        guard layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(local) else { return nil }
        let at = layout.characterIndexForGlyph(at: glyph)
        guard at < storage.length else { return nil }
        return storage.attribute(DevTreeLine.linkKey, at: at, effectiveRange: nil) as? URL
    }

    /// One menu for the tree: the line under the pointer's.
    func menu(at point: NSPoint) -> NSMenu? {
        guard let table, let parent, let line = line(table.row(at: point)) else { return nil }
        return parent.menu(line.node)
    }

    /// The node under the pointer drawn on the page; pointing leaves the
    /// tree, the drawing goes, as Chromium's onLeave.
    func pointed(_ point: NSPoint?) {
        guard let table else { return }
        let row = point.map { table.row(at: $0) } ?? -1
        guard row != hovered else { return }
        let before = hovered
        hovered = row
        for at in [before, row] where at >= 0 && at < table.numberOfRows {
            if let cell = table.view(atColumn: 0, row: at, makeIfNecessary: false) as? DevTreeCell { cell.hovered = at == hovered; cell.needsDisplay = true }
        }
        parent?.hover(line(row)?.node.id ?? 0)
    }

    /// After the rows moved under a still pointer (a scroll, a reload).
    private func pointedAgain() {
        guard let table, let window = table.window else { return }
        let point = table.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        pointed(table.visibleRect.contains(point) ? point : nil)
    }

    @objc func scrolled(_ note: Notification) {
        // The row at the top kept as it scrolls, to have the tree where it
        // was when it is shown again (DevReturn).
        if !steering, let top = topLine() { parent?.model.elementsTop = top.id }
        if hovered >= 0 { pointedAgain() }
    }

    @objc func resized(_ note: Notification) {
        fit(reload: true)
        runWaiting()
    }

    // MARK: in view

    private func topLine() -> (id: String, offset: CGFloat)? {
        guard let table, let clip = scroll?.contentView, !tree.lines.isEmpty else { return nil }
        // Above the first row, in the room over it: kept as far into that room.
        let y = clip.bounds.minY
        let row = table.row(at: NSPoint(x: 1, y: max(0, y)))
        guard let line = line(row) else { return nil }
        return (line.id, y - table.rect(ofRow: row).minY)
    }

    private func scrollTo(x: CGFloat? = nil, y: CGFloat? = nil) {
        guard let scroll, let table else { return }
        let clip = scroll.contentView
        var origin = clip.bounds.origin
        let inset = scroll.contentInsets
        if let x { origin.x = min(max(x, 0), max(0, table.frame.width - clip.bounds.width)) }
        if let y { origin.y = min(max(y, -inset.top), max(-inset.top, table.frame.height + inset.bottom - clip.bounds.height)) }
        guard origin != clip.bounds.origin else { return }
        clip.scroll(to: origin)
        scroll.reflectScrolledClipView(clip)
    }

    /// A line's words start just inside the left edge, as a node shown in
    /// Chrome's tree comes in from the side, unless they are in view.
    private func sideways(_ line: DevTreeLine, always: Bool) -> CGFloat? {
        guard let clip = scroll?.contentView, width > clip.bounds.width + 0.5 else { return nil }
        let start = DevTreeMetrics.textStart(line.depth)
        let seen = clip.bounds.minX + 24...max(clip.bounds.minX + 24, clip.bounds.maxX - 60)
        return always || !seen.contains(start) ? start - 24 : nil
    }

    /// Chrome's three ways of bringing a line into view: a node selected
    /// from elsewhere (the picker, find, the path, the start) comes to the
    /// middle when it is out of view (scrollIntoViewIfNeeded(true)); one
    /// selected from the keyboard comes in with the least scroll; a line
    /// pressed stays where it is. And the tree's top put back on a return.
    private func reveal(_ model: DevWorkbench, selectionMoved: Bool) {
        let top = model.elementsTopReveal != seen.top
        let key = model.elementsKeyReveal != seen.key
        let asked = model.elementsReveal != seen.reveal
        seen = (model.elementsReveal, model.elementsKeyReveal, model.elementsTopReveal)
        var act: (() -> Void)?
        if top, let id = model.elementsTop {
            act = { [weak self] in self?.showTop(id) }
        } else if key {
            model.keySelected = false
            act = { [weak self] in self?.show(model.selectedNode, close: model.selectedClose, least: true) }
        } else if asked {
            act = { [weak self] in self?.show(model.selectedNode, close: model.selectedClose, least: false) }
        } else if selectionMoved, !model.keySelected {
            if model.selectedNode == pressed { pressed = 0 } else {
                pressed = 0
                act = { [weak self] in self?.show(model.selectedNode, close: model.selectedClose, least: false) }
            }
        }
        if let act { later(act) }
    }

    private func show(_ node: Int, close: Bool, least: Bool) {
        guard let table, let clip = scroll?.contentView, let row = tree.at(node, close: close) ?? tree.at(node, close: false) else { return }
        let box = table.rect(ofRow: row)
        let visible = clip.bounds
        var y: CGFloat?
        if box.minY < visible.minY || box.maxY > visible.maxY {
            if least { y = box.minY < visible.minY ? box.minY : box.maxY - visible.height }
            else { y = box.midY - visible.height / 2 }
        }
        scrollTo(x: sideways(tree.lines[row], always: false), y: y)
    }

    private func showTop(_ id: String) {
        guard let table, let row = tree.place[id] else { return }
        // The row asked for stays the one kept, even where the end of the
        // tree holds it lower than the top.
        steering = true
        scrollTo(x: sideways(tree.lines[row], always: true) ?? 0, y: table.rect(ofRow: row).minY)
        steering = false
    }

    // MARK: for the bench

    /// Whether the selected line's row is wholly on screen, and the rows on
    /// screen with where each is in the window (top-left points).
    func shown(_ node: Int, close: Bool) -> Bool {
        guard let table, let clip = scroll?.contentView, let row = tree.at(node, close: close) else { return false }
        let box = table.rect(ofRow: row)
        return clip.bounds.insetBy(dx: -0.5, dy: -0.5).contains(CGRect(x: clip.bounds.minX + 1, y: box.minY, width: 1, height: box.height))
    }

    func rowsOnScreen() -> [[Any]] {
        guard let table, let content = table.window?.contentView else { return [] }
        let range = table.rows(in: table.visibleRect)
        var out: [[Any]] = []
        for row in range.location..<min(range.location + range.length, tree.lines.count) {
            let line = tree.lines[row]
            let box = table.convert(table.rect(ofRow: row), to: nil)
            let start = table.convert(NSPoint(x: DevTreeMetrics.textStart(line.depth), y: 0), to: nil).x
            out.append([line.id, Double(start), Double(content.bounds.height - box.maxY), Double(box.width), Double(box.height)])
            if out.count >= 60 { break }
        }
        return out
    }

    var scrollOffset: [Double] { scroll.map { [Double($0.contentView.bounds.minX), Double($0.contentView.bounds.minY)] } ?? [] }
    var editorShown: Bool { editField() != nil }
}

/// A line of the tree, drawn: its ground (selected, pointed at), the ⋯ of
/// the selected line, the triangle, the words; or the attributes' editor.
final class DevTreeCell: NSView {
    static let id = NSUserInterfaceItemIdentifier("devTreeLine")
    var line: DevTreeLine?
    var text: NSAttributedString?
    var picked = false
    var hovered = false
    var expanded = false
    var room: CGFloat = 0
    private(set) var field: NSTextField?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        identifier = Self.id
    }
    required init?(coder: NSCoder) { fatalError() }

    func edit(_ text: String?, delegate: NSTextFieldDelegate) {
        guard let text, let line else { field?.removeFromSuperview(); field = nil; return }
        let editor = field ?? {
            let made = NSTextField()
            made.isBordered = false
            made.drawsBackground = false
            made.focusRingType = .none
            made.font = DevTreeMetrics.font
            made.cell?.isScrollable = true
            made.cell?.wraps = false
            made.cell?.sendsActionOnEndEditing = false
            made.placeholderString = "Attributes"
            addSubview(made)
            field = made
            return made
        }()
        editor.delegate = delegate
        if editor.currentEditor() == nil { editor.stringValue = text }
        let start = DevTreeMetrics.textStart(line.depth)
        editor.frame = CGRect(x: start, y: 0, width: max(40, room), height: DevTreeMetrics.line)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let line else { return }
        if picked {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            bounds.fill()
        } else if hovered {
            Palette.NS.ink.withAlphaComponent(0.04).setFill()
            bounds.fill()
        }
        let muted = Palette.NS.muted
        if picked {
            let dots = NSAttributedString(string: "⋯", attributes: [.font: DevTreeMetrics.glyph, .foregroundColor: muted])
            let size = dots.size()
            dots.draw(at: NSPoint(x: (DevTreeMetrics.menu - size.width) / 2, y: (DevTreeMetrics.line - size.height) / 2))
        }
        if line.arrow {
            // Chrome's solid triangle, pointing right; down when open.
            let x = DevTreeMetrics.menu + CGFloat(line.depth) * DevTreeMetrics.indent + DevTreeMetrics.arrow / 2
            let y = DevTreeMetrics.line / 2
            let path = NSBezierPath()
            if expanded {
                path.move(to: NSPoint(x: x - 4, y: y - 2.5)); path.line(to: NSPoint(x: x + 4, y: y - 2.5)); path.line(to: NSPoint(x: x, y: y + 2.5))
            } else {
                path.move(to: NSPoint(x: x - 2.5, y: y - 4)); path.line(to: NSPoint(x: x + 2.5, y: y)); path.line(to: NSPoint(x: x - 2.5, y: y + 4))
            }
            path.close()
            muted.setFill()
            path.fill()
        }
        if let text {
            let start = DevTreeMetrics.textStart(line.depth)
            text.draw(with: CGRect(x: start, y: DevTreeMetrics.inset, width: room, height: max(0, bounds.height - DevTreeMetrics.inset)),
                      options: [.usesLineFragmentOrigin], context: nil)
        }
    }
}
