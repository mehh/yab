import AppKit
import SwiftUI

// Network's table and its overview, in AppKit (DevNet.swift): thousands of
// rows four times a second, columns that move, hide and sort, a menu on the
// head, keys and a waterfall drawn in each row. A SwiftUI list built and
// measured every row on each change; NSTableView keeps the rows on screen.

// MARK: - colors

/// Network's own colors: Chrome's for the waterfall's phases, which carry
/// meaning a hand already knows, and yab's for picking and failing.
enum NetInk {
    static func pair(_ light: Int, _ dark: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }
    }

    /// The same, each look with an alpha of its own.
    static func pair(_ light: Int, _ dark: Int, alphas: (light: CGFloat, dark: CGFloat)) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: isDark ? alphas.dark : alphas.light)
        }
    }

    static let queueing = pair(0xFFFFFF, 0x2A2A2A)
    static let stalled = pair(0xBCBCBC, 0x6E6E6E)
    static let dns = pair(0x12A4AF, 0x2BC3CE)
    static let connecting = pair(0xE2A40B, 0xF0B93A)
    static let ssl = pair(0x9334E6, 0xB57BF0)
    static let sending = pair(0x4ECDE6, 0x7FDDEF)
    static let waiting = pair(0x1E8E3E, 0x3DBE65)
    static let download = pair(0x4285F4, 0x6EA3F7)
    static let contentLoaded = pair(0x1A73E8, 0x8AB4F8)
    static let loaded = pair(0xD93025, 0xF28B82)
    static let shot = pair(0xE2A40B, 0xF0B93A)
    /// A mark that has to be seen (a filter on, an override, a range's
    /// edges): the system's accent, not a color of Yab's own.
    static var accent: NSColor { .controlAccentColor }
    /// The picked row, message or range: the system's selection gray.
    static var picked: NSColor { .unemphasizedSelectedContentBackgroundColor }
    static let red = pair(0xE5484D, 0xFF6369)
    static let redWash = pair(0xE5484D, 0xFF6369, alpha: 0.08)
    static let amber = pair(0xB07D00, 0xF2C14E)
    static let up = pair(0x1E8E3E, 0x3DD68C, alpha: 0.16)
    static let down = pair(0xE5484D, 0xFF6369, alpha: 0.14)
    static let stripe = Palette.NS.hover
    /// A request Search found its words in: Chrome's search yellow.
    static let found = pair(0xF9AB00, 0xFDD663, alpha: 0.24)

    static func phase(_ phase: NetPhases.Phase) -> NSColor {
        switch phase {
        case .queueing: return queueing
        case .stalled: return stalled
        case .dns: return dns
        case .connecting: return connecting
        case .ssl: return ssl
        case .sending: return sending
        case .waiting: return waiting
        case .download: return download
        }
    }

    /// The chip's color for a type, the little square before a name.
    static func type(_ category: NetCategory) -> NSColor {
        switch category {
        case .doc: return pair(0x2B6CDF, 0x6EA3F7)
        case .js: return pair(0xD1A100, 0xF0C33A)
        case .css: return pair(0x7B4FD9, 0xA98BF0)
        case .img: return pair(0x1E9A5A, 0x3DD68C)
        case .media: return pair(0xB8418A, 0xE07AB8)
        case .font: return pair(0x6B6B6B, 0xA0A0A0)
        case .fetch: return pair(0xD9632B, 0xF08A5A)
        case .socket: return pair(0x0F8A8A, 0x2BC3CE)
        case .wasm: return pair(0x654FF0, 0x9A8BFF)
        case .manifest: return pair(0x5F6B7A, 0x8A96A5)
        case .other: return pair(0x8C8C8C, 0x8C8C8C)
        }
    }

    /// What the chip says, as the design drew it: a letter or two for the type.
    static func letters(_ category: NetCategory) -> String {
        switch category {
        case .doc: return "D"
        case .js: return "JS"
        case .css: return "C"
        case .img: return "I"
        case .media, .manifest: return "M"
        case .font: return "F"
        case .fetch: return "{}"
        case .socket: return "WS"
        case .wasm: return "W"
        case .other: return "·"
        }
    }
}

// MARK: - columns

/// A column of the table, Chrome's, by its id in Settings.
struct NetColumn: Equatable {
    let id: String
    let title: String
    let width: CGFloat
    var right = false

    static let defaults = ["name", "status", "type", "initiator", "size", "time", "waterfall"]

    /// Response headers and request headers Chrome offers as columns.
    static let responseHeaders = ["Cache-Control", "Connection", "Content-Encoding", "Content-Length", "ETag", "Keep-Alive", "Last-Modified", "Server", "Vary"]
    static let requestHeaders = ["Accept", "Accept-Encoding", "Accept-Language", "Content-Type", "Origin", "Referer", "Sec-Fetch-Dest", "Sec-Fetch-Mode", "User-Agent"]

    /// The columns the head's menu lists, in Chrome's order.
    static let listed: [NetColumn] = [
        NetColumn(id: "number", title: "Request #", width: 64, right: true),
        NetColumn(id: "name", title: "Name", width: 220),
        NetColumn(id: "path", title: "Path", width: 180),
        NetColumn(id: "url", title: "URL", width: 240),
        NetColumn(id: "method", title: "Method", width: 64),
        NetColumn(id: "status", title: "Status", width: 64),
        NetColumn(id: "protocol", title: "Protocol", width: 64),
        NetColumn(id: "scheme", title: "Scheme", width: 60),
        NetColumn(id: "domain", title: "Domain", width: 140),
        NetColumn(id: "remote", title: "Remote address", width: 130),
        NetColumn(id: "space", title: "Remote address space", width: 96),
        NetColumn(id: "ispace", title: "Initiator address space", width: 96),
        NetColumn(id: "type", title: "Type", width: 84),
        NetColumn(id: "initiator", title: "Initiator", width: 130),
        NetColumn(id: "cookies", title: "Cookies", width: 60, right: true),
        NetColumn(id: "setcookies", title: "Set cookies", width: 72, right: true),
        NetColumn(id: "size", title: "Size", width: 76, right: true),
        NetColumn(id: "time", title: "Time", width: 72, right: true),
        NetColumn(id: "priority", title: "Priority", width: 64),
        NetColumn(id: "connection", title: "Connection ID", width: 76, right: true),
        NetColumn(id: "overrides", title: "Has overrides", width: 84),
        NetColumn(id: "waterfall", title: "Waterfall", width: 240),
    ]

    static func named(_ id: String) -> NetColumn? {
        if let column = listed.first(where: { $0.id == id }) { return column }
        if id.hasPrefix("h:") { return NetColumn(id: id, title: String(id.dropFirst(2)), width: 110, right: id.lowercased() == "h:content-length") }
        if id.hasPrefix("q:") { return NetColumn(id: id, title: String(id.dropFirst(2)), width: 120) }
        return nil
    }
}

/// The time the waterfall and overview draw: from the earliest start,
/// as long as the latest end or the page's load, a little past it.
struct NetScale: Equatable {
    var origin: Double
    var span: Double

    func x(_ moment: Double, in width: CGFloat) -> CGFloat {
        guard span > 0 else { return 0 }
        return CGFloat((moment - origin) / span) * width
    }

    static func of(_ rows: [NetRow], contentLoaded: Double?, loaded: Double?, horizon: Double?) -> NetScale {
        let starts = rows.lazy.map(\.span.start).filter { $0 > 0 }
        guard let origin = starts.min() else { return NetScale(origin: 0, span: 1) }
        var end = rows.lazy.compactMap(\.span.end).max() ?? origin
        if let horizon { end = max(end, horizon) }
        if let loaded { end = max(end, loaded) }
        if let contentLoaded { end = max(end, contentLoaded) }
        return NetScale(origin: origin, span: max(0.1, (end - origin) * 1.04))
    }
}

/// An item of the table: a request, or a frame's heading when the rows are
/// grouped by frame.
enum NetItem: Equatable {
    case row(NetRow)
    case frame(String)

    var row: NetRow? { if case .row(let row) = self { return row } else { return nil } }
}

// MARK: - the table

struct NetTableView: NSViewRepresentable {
    struct Model: Equatable {
        var items: [NetItem]
        var numbers: [Int: Int]
        var columns: [String]
        var selected: Int?
        var up: Set<Int>
        var down: Set<Int>
        /// Found by Search: lit, as each place a match is.
        var found: Set<Int> = []
        var big: Bool
        var scale: NetScale
        var horizon: Double?
        var contentLoaded: Double?
        var loaded: Double?
        var sort: NetSort?
        var overridden: [Int: String]
        var empty: String?
        /// Where the page itself is: Loopback, Local or Public.
        var pageSpace = ""
    }

    let model: Model
    var select: (Int?) -> Void
    var open: (NetRow) -> Void
    var sortBy: (String) -> Void
    var hover: (Int?, Bool) -> Void
    var resend: (NetRow) -> Void
    var rowMenu: (NetRow) -> NSMenu
    var headMenu: () -> NSMenu
    var reveal: (NetRow) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let table = NetTable()
        table.coordinator = context.coordinator
        table.headerView = NetHeadView()
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.gridStyleMask = []
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.focusRingType = .none
        if table.responds(to: NSSelectorFromString("setStyle:")) { table.style = .plain }
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        let menu = NSMenu()
        menu.delegate = context.coordinator
        table.menu = menu
        let head = NSMenu()
        head.delegate = context.coordinator
        table.headerView?.menu = head
        context.coordinator.table = table
        scroll.documentView = table
        // The waterfall, last, takes whatever width the table is given.
        scroll.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.resized(_:)),
                                               name: NSView.frameDidChangeNotification, object: scroll.contentView)
        ThreadScroller.put(on: scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(model)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: NetTableView!
        weak var table: NetTable?
        private(set) var model: Model?
        private var choosing = false

        func update(_ next: Model) {
            guard let table else { return }
            let before = model
            model = next
            if before?.columns != next.columns { layColumns(next.columns) }
            if before?.sort != next.sort || before?.columns != next.columns {
                for column in table.tableColumns {
                    let on = next.sort?.column == column.identifier.rawValue
                    (column.headerCell as? NetHeaderCell)?.sorted = on ? next.sort?.ascending : nil
                }
                table.headerView?.needsDisplay = true
            }
            table.rowHeight = next.big ? 38 : 21
            let sameRows = before.map { $0.items.count == next.items.count && zip($0.items, next.items).allSatisfy { a, b in
                a.row?.id == b.row?.id && (a.row != nil || a == b) } } ?? false
            // How far a request still coming has got matters only while one is.
            let moving = next.horizon != before?.horizon && next.items.contains { $0.row?.pending == true }
            let redraw = before.map { $0.big != next.big || $0.scale != next.scale || moving || $0.up != next.up || $0.down != next.down || $0.found != next.found
                || $0.contentLoaded != next.contentLoaded || $0.loaded != next.loaded || $0.overridden != next.overridden || $0.columns != next.columns } ?? true
            if !sameRows || redraw {
                table.reloadData()
            } else if let before {
                var changed = IndexSet()
                for (index, (a, b)) in zip(before.items, next.items).enumerated() where a != b { changed.insert(index) }
                if !changed.isEmpty { table.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns)) }
            }
            choose(next.selected)
            table.empty = next.items.isEmpty ? next.empty : nil
        }

        private func choose(_ id: Int?) {
            guard let table, let model else { return }
            let index = id.flatMap { id in model.items.firstIndex { $0.row?.id == id } } ?? -1
            guard table.selectedRow != index else { return }
            choosing = true
            if index >= 0 {
                table.selectRowIndexes([index], byExtendingSelection: false)
                table.scrollRowToVisible(index)
            } else {
                table.deselectAll(nil)
            }
            choosing = false
        }

        private func layColumns(_ ids: [String]) {
            guard let table else { return }
            let widths = Dictionary(uniqueKeysWithValues: table.tableColumns.map { ($0.identifier.rawValue, $0.width) })
            for column in table.tableColumns { table.removeTableColumn(column) }
            for id in ids {
                guard let spec = NetColumn.named(id) else { continue }
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
                column.title = spec.title
                column.minWidth = id == "waterfall" ? 80 : 36
                column.maxWidth = 4000
                column.width = widths[id] ?? spec.width
                column.resizingMask = .userResizingMask
                column.headerCell = NetHeaderCell(textCell: spec.title)
                column.headerCell.alignment = spec.right ? .right : .left
                table.addTableColumn(column)
            }
            fit()
        }

        /// The last column takes what is left, as Chromium's waterfall does.
        /// By hand: sizeLastColumnToFit leaves a column that only the user
        /// may resize as wide as it was.
        func fit() {
            guard let table, let last = table.tableColumns.last, let clip = table.enclosingScrollView?.contentView else { return }
            let others = table.tableColumns.dropLast().reduce(0) { $0 + $1.width }
            let width = max(last.minWidth, clip.bounds.width - others)
            if abs(last.width - width) > 0.5 { last.width = width }
        }

        // MARK: data

        func numberOfRows(in tableView: NSTableView) -> Int { model?.items.count ?? 0 }

        /// The item at a row, or nil past the model's end. The table asks by
        /// the row count it last loaded: `update` takes the new model first,
        /// and re-laying the columns tiles the table, which asks about the
        /// old rows before the reload that follows (0.0.15 trapped here,
        /// crash #26, when a filter or a cleared log left fewer rows).
        func item(at row: Int) -> NetItem? {
            guard let model, model.items.indices.contains(row) else { return nil }
            return model.items[row]
        }

        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            if case .frame = item(at: row) { return true }
            return false
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            if case .frame = item(at: row) { return 22 }
            return model?.big == true ? 38 : 21
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let view = tableView.makeView(withIdentifier: NetRowView.id, owner: nil) as? NetRowView ?? {
                let made = NetRowView()
                made.identifier = NetRowView.id
                return made
            }()
            if let net = item(at: row)?.row {
                view.bad = net.bad
                view.stripe = row % 2 == 1
                view.up = model?.up.contains(net.id) == true
                view.down = model?.down.contains(net.id) == true
                view.found = model?.found.contains(net.id) == true
                view.heading = false
            } else {
                view.bad = false; view.stripe = false; view.up = false; view.down = false; view.found = false
                view.heading = true
            }
            return view
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let model, row < model.items.count else { return nil }
            switch model.items[row] {
            case .frame(let title):
                guard tableColumn == nil || tableColumn === tableView.tableColumns.first else { return nil }
                let cell = tableView.makeView(withIdentifier: NetTextCell.heading, owner: nil) as? NetTextCell ?? NetTextCell(id: NetTextCell.heading)
                cell.set(title, second: nil, right: false, ink: Palette.NS.ink, weight: .semibold, tip: title)
                return cell
            case .row(let net):
                guard let id = tableColumn?.identifier.rawValue else { return nil }
                return cell(id, net, in: tableView, model: model)
            }
        }

        private func cell(_ id: String, _ row: NetRow, in table: NSTableView, model: Model) -> NSView {
            let ink: NSColor = row.bad ? NetInk.red : row.resource.throttledBy != nil ? NetInk.amber : row.pending && !row.streaming ? Palette.NS.muted : Palette.NS.ink
            let big = model.big
            func text(_ first: String, _ second: String? = nil, right: Bool = false, tip: String? = nil, color: NSColor? = nil, link: Bool = false) -> NSView {
                let cell = table.makeView(withIdentifier: NetTextCell.plain, owner: nil) as? NetTextCell ?? NetTextCell(id: NetTextCell.plain)
                cell.set(first, second: big ? second : nil, right: right, ink: color ?? ink, weight: .regular, tip: tip, link: link)
                return cell
            }
            switch id {
            case "name":
                let cell = table.makeView(withIdentifier: NetNameCell.id, owner: nil) as? NetNameCell ?? NetNameCell()
                cell.set(row, big: big, ink: ink, overridden: model.overridden[row.id])
                return cell
            case "number": return text(model.numbers[row.id].map(String.init) ?? "", right: true, color: Palette.NS.muted)
            case "path": return text(row.path, tip: row.url)
            case "url": return text(row.url, tip: row.url)
            case "method": return text(row.method)
            case "status": return text(row.statusLabel, row.statusWords, tip: row.statusWords.isEmpty ? nil : row.statusWords)
            case "protocol": return text(row.hop == nil ? row.resource.proto : "")
            case "scheme": return text(row.scheme)
            case "domain": return text(row.host)
            case "remote": return text(row.hop == nil ? row.resource.remote : "")
            case "space": return text(row.hop == nil ? NetAddress.space(row.resource.remote) : "")
            case "ispace": return text(model.pageSpace)
            case "type": return text(row.typeLabel, row.fromCache ? "from cache" : nil)
            case "initiator":
                let initiator = row.initiatorLabel
                let linked = row.resource.initiator.kind == .parser || row.resource.initiator.kind == .script || row.from != nil
                return text(initiator.place, initiator.kind.isEmpty ? nil : initiator.kind, tip: row.resource.initiator.url.isEmpty ? nil : row.resource.initiator.url,
                            color: linked && !row.bad ? .linkColor : nil, link: linked)
            case "cookies": return text(NetCookie.request(row).count.nonZero, right: true)
            case "setcookies": return text(NetCookie.response(row).cookies.count.nonZero, right: true)
            case "size":
                if row.failed { return text("0 B", "0 B", right: true) }
                if let from = row.fromCacheLabel { return text(from, NetFormat.size(row.size), right: true, color: Palette.NS.muted) }
                return text(row.pending && !row.streaming ? "0 B" : NetFormat.size(row.transferred), NetFormat.size(row.size), right: true)
            case "time":
                if row.failed { return text("0 ms", right: true) }
                let first = row.duration.map(NetFormat.time) ?? "Pending"
                let latency = row.phases.map { NetFormat.time($0.latency) }
                if let rule = row.resource.throttledBy {
                    let cell = table.makeView(withIdentifier: NetTextCell.plain, owner: nil) as? NetTextCell ?? NetTextCell(id: NetTextCell.plain)
                    cell.set("◷ " + first, second: big ? latency : nil, right: true, ink: NetInk.amber, weight: .regular, tip: "Request was throttled (\(rule))")
                    return cell
                }
                return text(first, latency, right: true)
            case "priority": return text(row.hop == nil ? row.resource.priority.capitalized : "")
            case "connection": return text(row.hop == nil ? row.resource.connection : "", right: true)
            case "overrides":
                let kind = model.overridden[row.id]
                return text(kind == "both" ? "content, headers" : kind ?? "")
            case "waterfall":
                let cell = table.makeView(withIdentifier: NetWaterfallCell.id, owner: nil) as? NetWaterfallCell ?? NetWaterfallCell()
                cell.set(row, scale: model.scale, horizon: model.horizon, contentLoaded: model.contentLoaded, loaded: model.loaded)
                return cell
            default:
                if id.hasPrefix("h:") { return text(row.responseHeaders.value(String(id.dropFirst(2))) ?? "", right: id.lowercased() == "h:content-length") }
                if id.hasPrefix("q:") { return text(row.requestHeaders.value(String(id.dropFirst(2))) ?? "") }
                return text("")
            }
        }

        // MARK: picking

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !choosing, let table, let model else { return }
            let index = table.selectedRow
            let id = index >= 0 && index < model.items.count ? model.items[index].row?.id : nil
            if id != model.selected { parent.select(id) }
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            item(at: row)?.row != nil
        }

        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            parent.sortBy(tableColumn.identifier.rawValue)
        }

        @objc func resized(_ note: Notification) { fit() }

        func tableViewColumnDidResize(_ notification: Notification) {
            guard let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn, column != table?.tableColumns.last else { return }
            fit()
        }

        @objc func doubleClicked(_ sender: Any?) {
            guard let table, let model, table.clickedRow >= 0, table.clickedRow < model.items.count, let row = model.items[table.clickedRow].row else { return }
            parent.open(row)
        }

        func row(at index: Int) -> NetRow? {
            guard let model, index >= 0, index < model.items.count else { return nil }
            return model.items[index].row
        }

        func hovered(_ index: Int, shift: Bool) {
            parent.hover(row(at: index)?.id, shift)
        }

        func clickedInitiator(_ index: Int) {
            guard let row = row(at: index) else { return }
            parent.reveal(row)
        }

        func resendPicked() {
            guard let table, let row = row(at: table.selectedRow) else { return }
            parent.resend(row)
        }

        func closeDetails() { parent.select(nil) }

        // MARK: menus

        func menuNeedsUpdate(_ menu: NSMenu) {
            guard let table else { return }
            menu.removeAllItems()
            let built: NSMenu
            if menu === table.headerView?.menu {
                built = parent.headMenu()
            } else {
                guard let row = row(at: table.clickedRow) else { return }
                built = parent.rowMenu(row)
            }
            for item in built.items {
                built.removeItem(item)
                menu.addItem(item)
            }
        }
    }
}

private extension Int {
    var nonZero: String { self == 0 ? "" : String(self) }
}

/// Where an address is: this Mac, the local network, or out there.
enum NetAddress {
    static func space(_ remote: String) -> String {
        guard !remote.isEmpty else { return "" }
        var host = remote
        if host.hasPrefix("["), let end = host.firstIndex(of: "]") { host = String(host[host.index(after: host.startIndex)..<end]) }
        else if let colon = host.lastIndex(of: ":"), host.filter({ $0 == ":" }).count == 1 { host = String(host[..<colon]) }
        if host == "::1" || host.hasPrefix("127.") || host == "localhost" { return "Loopback" }
        if host.hasPrefix("10.") || host.hasPrefix("192.168.") || host.hasPrefix("169.254.") || host.lowercased().hasPrefix("fe80") || host.lowercased().hasPrefix("fd") { return "Local" }
        if host.hasPrefix("172."), let second = Int(host.split(separator: ".").dropFirst().first ?? ""), (16...31).contains(second) { return "Local" }
        return "Public"
    }
}

/// The table: its keys and the pointer, for the coordinator.
final class NetTable: NSTableView {
    weak var coordinator: NetTableView.Coordinator?
    /// Said in the middle when there is nothing to list.
    var empty: String? { didSet { if empty != oldValue { needsDisplay = true } } }
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        coordinator?.hovered(row(at: point), shift: event.modifierFlags.contains(.shift))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        coordinator?.hovered(-1, shift: false)
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        coordinator?.hovered(row(at: point), shift: event.modifierFlags.contains(.shift))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point), column = column(at: point)
        // The initiator's link: its place in Sources, as Chromium's link does.
        if row >= 0, column >= 0, tableColumns[column].identifier.rawValue == "initiator", event.clickCount == 1 {
            coordinator?.clickedInitiator(row)
            return
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        if flags.isEmpty, event.charactersIgnoringModifiers?.lowercased() == "r" {
            coordinator?.resendPicked()
            return
        }
        if flags.isEmpty, event.keyCode == 36 || event.keyCode == 49 { return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        coordinator?.closeDetails()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let empty, numberOfRows == 0 else { return }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let words = NSAttributedString(string: empty, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Palette.NS.muted, .paragraphStyle: style])
        let visible = enclosingScrollView?.documentVisibleRect ?? bounds
        let size = words.boundingRect(with: NSSize(width: visible.width - 40, height: 200), options: [.usesLineFragmentOrigin]).size
        words.draw(with: NSRect(x: visible.minX + 20, y: visible.midY - size.height / 2, width: visible.width - 40, height: size.height + 4), options: [.usesLineFragmentOrigin])
    }
}

final class NetHeadView: NSTableHeaderView {
    override var frame: NSRect {
        get { super.frame }
        set { var f = newValue; f.size.height = 22; super.frame = f }
    }
}

/// The head's cells: small words, no system gradient.
final class NetHeaderCell: NSTableHeaderCell {
    /// Sorted by this column: up ascending, down descending, as Chromium's
    /// triangle at the head's end.
    var sorted: Bool?

    override init(textCell: String) {
        super.init(textCell: textCell)
        font = NSFont.systemFont(ofSize: 11, weight: .medium)
        textColor = Palette.NS.muted
    }

    required init(coder: NSCoder) { fatalError() }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        Palette.NS.ground.setFill()
        cellFrame.fill()
        Palette.NS.hairline.setFill()
        NSRect(x: cellFrame.maxX - 1, y: cellFrame.minY + 3, width: 1, height: cellFrame.height - 6).fill()
        NSRect(x: cellFrame.minX, y: cellFrame.maxY - 1, width: cellFrame.width, height: 1).fill()
        // The words where a row's cell has its own, 6 points in from either
        // edge; a triangle takes the end and right-set words step past it.
        var room = cellFrame.insetBy(dx: 6, dy: 0)
        if let up = sorted {
            let mark = NSRect(x: room.maxX - 7, y: cellFrame.midY - 2.5, width: 7, height: 5)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: mark.minX, y: up ? mark.maxY : mark.minY))
            path.line(to: NSPoint(x: mark.maxX, y: up ? mark.maxY : mark.minY))
            path.line(to: NSPoint(x: mark.midX, y: up ? mark.minY : mark.maxY))
            path.close()
            Palette.NS.muted.setFill()
            path.fill()
            room.size.width -= 11
        }
        drawInterior(withFrame: room, in: controlView)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let words = NSAttributedString(string: stringValue, attributes: [.font: font ?? NSFont.systemFont(ofSize: 11), .foregroundColor: Palette.NS.muted])
        let size = words.size()
        let x = alignment == .right ? cellFrame.maxX - size.width : cellFrame.minX
        words.draw(at: NSPoint(x: x, y: (cellFrame.midY - size.height / 2).rounded()))
    }
}

/// A row: its stripe, red when it failed, the system's selection gray when picked, and
/// with Shift held what asked for it green and what it asked for red.
final class NetRowView: NSTableRowView {
    static let id = NSUserInterfaceItemIdentifier("net-row")
    var bad = false
    var stripe = false
    var up = false
    var down = false
    var found = false
    var heading = false

    override func drawBackground(in dirtyRect: NSRect) {
        let color: NSColor? = heading ? Palette.NS.wash : up ? NetInk.up : down ? NetInk.down : found ? NetInk.found : bad ? NetInk.redWash : stripe ? NetInk.stripe : nil
        if let color {
            color.setFill()
            bounds.fill()
        }
        // The table draws no selection of its own (no system blue), so the
        // picked row's gray is laid here, over its stripe.
        if isSelected {
            NetInk.picked.setFill()
            bounds.fill()
        }
        if down {
            NetInk.red.setFill()
            NSRect(x: 0, y: 0, width: 2, height: bounds.height).fill()
        }
    }

    override var isSelected: Bool { didSet { if isSelected != oldValue { needsDisplay = true } } }

    override var isEmphasized: Bool { get { false } set {} }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

/// Words in a cell, a second line under them in big rows.
final class NetTextCell: NSTableCellView {
    static let plain = NSUserInterfaceItemIdentifier("net-text")
    static let heading = NSUserInterfaceItemIdentifier("net-heading")
    private let first = NSTextField(labelWithString: "")
    private let second = NSTextField(labelWithString: "")
    private let stack = NSStackView()

    init(id: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        identifier = id
        for label in [first, second] {
            label.lineBreakMode = .byTruncatingTail
            label.cell?.truncatesLastVisibleLine = true
            label.maximumNumberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        first.font = NSFont.systemFont(ofSize: 12)
        second.font = NSFont.systemFont(ofSize: 10.5)
        second.textColor = Palette.NS.muted
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.addArrangedSubview(first)
        stack.addArrangedSubview(second)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(_ text: String, second words: String?, right: Bool, ink: NSColor, weight: NSFont.Weight, tip: String?, link: Bool = false) {
        first.stringValue = text
        first.textColor = ink
        // Sizes and times right-set in figures of one width, so they line up.
        first.font = right ? NSFont.monospacedDigitSystemFont(ofSize: 12, weight: weight) : NSFont.systemFont(ofSize: 12, weight: weight)
        first.alignment = right ? .right : .left
        if link {
            first.attributedStringValue = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: ink,
                .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: ink.withAlphaComponent(0.35),
                .paragraphStyle: { let p = NSMutableParagraphStyle(); p.alignment = right ? .right : .left; p.lineBreakMode = .byTruncatingTail; return p }(),
            ])
        }
        second.stringValue = words ?? ""
        second.alignment = right ? .right : .left
        second.isHidden = words == nil
        stack.alignment = right ? .trailing : .leading
        keyTip(tip)
    }
}

/// The name, after a square in its type's color with the type's letters
/// on it; the path under it in big rows. A dot on the square for an
/// override.
final class NetNameCell: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("net-name")
    private let chip = NSView()
    private let letters = NSTextField(labelWithString: "")
    private let dot = NSView()
    private let first = NSTextField(labelWithString: "")
    private let second = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.id
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 3
        letters.font = NSFont.systemFont(ofSize: 7.5, weight: .bold)
        letters.textColor = .white
        letters.alignment = .center
        letters.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(letters)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.layer?.backgroundColor = NetInk.accent.cgColor
        dot.layer?.borderWidth = 1.5
        for label in [first, second] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        first.font = NSFont.systemFont(ofSize: 12)
        second.font = NSFont.systemFont(ofSize: 10.5)
        second.textColor = Palette.NS.muted
        let words = NSStackView(views: [first, second])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 1
        for view in [chip, words, dot] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            chip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            chip.centerYAnchor.constraint(equalTo: centerYAnchor),
            chip.widthAnchor.constraint(equalToConstant: 14),
            chip.heightAnchor.constraint(equalToConstant: 14),
            letters.centerXAnchor.constraint(equalTo: chip.centerXAnchor),
            letters.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            dot.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: 3),
            dot.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: 3),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            words.leadingAnchor.constraint(equalTo: chip.trailingAnchor, constant: 6),
            words.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            words.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(_ row: NetRow, big: Bool, ink: NSColor, overridden: String?) {
        // Its type's color even when it failed: the words say that, in red.
        chip.layer?.backgroundColor = NetInk.type(row.category).cgColor
        letters.stringValue = NetInk.letters(row.category)
        dot.isHidden = overridden == nil
        dot.layer?.borderColor = Palette.NS.ground.cgColor
        first.stringValue = row.name
        first.textColor = ink
        second.stringValue = row.resource.type == "document" ? row.path : row.hostAndPort + (row.path.components(separatedBy: "/").dropLast().joined(separator: "/") + "/")
        second.isHidden = !big
        keyTip(row.url)
    }
}

/// A row's place in the waterfall: its phases end to end, in Chrome's
/// colors, and the page's DOMContentLoaded and Load as lines through it.
final class NetWaterfallCell: NSView {
    static let id = NSUserInterfaceItemIdentifier("net-waterfall")
    private var row: NetRow?
    private var scale = NetScale(origin: 0, span: 1)
    private var horizon: Double?
    private var contentLoaded: Double?
    private var loaded: Double?

    init() {
        super.init(frame: .zero)
        identifier = Self.id
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(_ row: NetRow, scale: NetScale, horizon: Double?, contentLoaded: Double?, loaded: Double?) {
        self.row = row
        self.scale = scale
        self.horizon = horizon
        self.contentLoaded = contentLoaded
        self.loaded = loaded
        needsDisplay = true
        if let phases = row.phases, phases.total > 0 {
            let lines = NetPhases.Phase.allCases.compactMap { phase -> String? in
                let v = phases.value(phase)
                return v > 0 ? "\(phase.rawValue)  \(NetFormat.time(v))" : nil
            }
            keyTip(([row.name] + lines + ["Total  \(row.duration.map(NetFormat.time) ?? "Pending")"]).joined(separator: "\n"))
        } else {
            keyTip(nil)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width - 8
        let inset: CGFloat = 4
        for (moment, color) in [(contentLoaded, NetInk.contentLoaded), (loaded, NetInk.loaded)] {
            guard let moment else { continue }
            color.setFill()
            NSRect(x: inset + scale.x(moment, in: w).rounded(), y: 0, width: 1, height: bounds.height).fill()
        }
        // What the page held before the inspector was up has no moment.
        guard let row, row.resource.blockedBy == nil, row.span.start > 0 else { return }
        let span = row.span
        let end = span.end ?? max(horizon ?? span.start, span.start)
        let x0 = inset + scale.x(span.start, in: w)
        let x1 = max(x0 + 1.5, inset + scale.x(end, in: w))
        let barHeight: CGFloat = min(9, bounds.height - 6)
        let y = (bounds.height - barHeight) / 2
        if row.failed {
            NetInk.red.withAlphaComponent(0.55).setFill()
            NSRect(x: x0, y: y, width: x1 - x0, height: barHeight).fill()
            return
        }
        guard let phases = row.phases, phases.total > 0 else {
            (row.fromCache ? Palette.NS.faint : NetInk.download).setFill()
            NSRect(x: x0, y: y, width: x1 - x0, height: barHeight).fill()
            return
        }
        let total = max(phases.total, ((end - span.start) * 1000))
        var x = x0
        let width = x1 - x0
        for phase in NetPhases.Phase.allCases {
            var value = phase == .download && row.pending ? max(0, total - phases.latency) : phases.value(phase)
            if phase == .download && row.pending { value = max(value, 0) }
            guard value > 0 else { continue }
            let part = CGFloat(value / total) * width
            let rect = NSRect(x: x, y: y, width: max(part, 0.5), height: barHeight)
            NetInk.phase(phase).setFill()
            rect.fill()
            if phase == .queueing {
                Palette.NS.faint.setStroke()
                NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
            }
            x += part
        }
    }

    override var isFlipped: Bool { true }
}

// MARK: - the overview

/// The strip over the table: every request as a thin line in its lane,
/// DOMContentLoaded and Load, the time along the top, and a stretch to
/// filter by, drawn with the pointer and let go of with a double click.
struct NetOverview: NSViewRepresentable {
    struct Model: Equatable {
        var rows: [NetRow]
        var scale: NetScale
        var horizon: Double?
        var contentLoaded: Double?
        var loaded: Double?
        var range: ClosedRange<Double>?
        var shot: Double?
    }

    let model: Model
    var pick: (ClosedRange<Double>?) -> Void

    func makeNSView(context: Context) -> NetOverviewView {
        let view = NetOverviewView()
        view.pick = pick
        return view
    }

    func updateNSView(_ view: NetOverviewView, context: Context) {
        view.pick = pick
        if view.model != model {
            view.model = model
            view.needsDisplay = true
        }
    }
}

final class NetOverviewView: NSView {
    var model: NetOverview.Model?
    var pick: ((ClosedRange<Double>?) -> Void)?
    private var from: Double?

    override var isFlipped: Bool { true }

    private func moment(_ event: NSEvent) -> Double {
        guard let model else { return 0 }
        let x = convert(event.locationInWindow, from: nil).x
        return model.scale.origin + Double(max(0, min(1, x / max(1, bounds.width)))) * model.scale.span
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { from = nil; pick?(nil); return }
        from = moment(event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let from, let model else { return }
        let to = moment(event)
        guard abs(to - from) > model.scale.span / 300 else { return }
        pick?(min(from, to)...max(from, to))
    }

    override func mouseUp(with event: NSEvent) { from = nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        let w = bounds.width, h = bounds.height
        // The time along the top.
        let seconds = model.scale.span
        let step = Self.step(seconds / 8)
        var t = step
        let font = NSFont.systemFont(ofSize: 10)
        while t < seconds {
            let x = (CGFloat(t / seconds) * w).rounded() + 0.5
            Palette.NS.hairline.setFill()
            NSRect(x: x, y: 0, width: 1, height: h).fill()
            let label = t >= 1 ? (t.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(t)) s" : String(format: "%.1f s", t)) : "\(Int((t * 1000).rounded())) ms"
            // 3 points past its line, as the design draws them.
            NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: Palette.NS.muted]).draw(at: NSPoint(x: x + 3, y: 1))
            t += step
        }
        // Every request in the first lane free at its start.
        var lanes: [Double] = []
        let sorted = model.rows.sorted { $0.span.start < $1.span.start }
        for row in sorted where row.resource.blockedBy == nil && row.span.start > 0 {
            let span = row.span
            let end = span.end ?? max(model.horizon ?? span.start, span.start)
            var lane = lanes.firstIndex { $0 <= span.start } ?? lanes.count
            if lane == lanes.count { lanes.append(end) } else { lanes[lane] = end }
            lane = min(lane, 12)
            let y = 16 + CGFloat(lane) * 3
            let x0 = model.scale.x(span.start, in: w), x1 = max(x0 + 1, model.scale.x(end, in: w))
            let latency = row.phases.map { span.start + $0.latency / 1000 } ?? end
            let xw = min(x1, max(x0, model.scale.x(latency, in: w)))
            (row.failed ? NetInk.red : NetInk.waiting).setFill()
            NSRect(x: x0, y: y, width: max(1, xw - x0), height: 2).fill()
            if x1 > xw {
                (row.failed ? NetInk.red : NetInk.download).setFill()
                NSRect(x: xw, y: y, width: x1 - xw, height: 2).fill()
            }
        }
        for (moment, color) in [(model.contentLoaded, NetInk.contentLoaded), (model.loaded, NetInk.loaded), (model.shot, NetInk.shot)] {
            guard let moment else { continue }
            color.setFill()
            NSRect(x: model.scale.x(moment, in: w).rounded(), y: 0, width: 1, height: h).fill()
        }
        if let range = model.range {
            let x0 = model.scale.x(range.lowerBound, in: w), x1 = model.scale.x(range.upperBound, in: w)
            NetInk.picked.setFill()
            NSRect(x: x0, y: 0, width: max(1, x1 - x0), height: h).fill()
            NetInk.accent.setFill()
            NSRect(x: x0, y: 0, width: 1, height: h).fill()
            NSRect(x: x1 - 1, y: 0, width: 1, height: h).fill()
        }
    }

    static func step(_ x: Double) -> Double {
        guard x > 0 else { return 1 }
        let p = pow(10, floor(log10(x)))
        let n = x / p
        return (n < 1.5 ? 1 : n < 3.5 ? 2 : n < 7.5 ? 5 : 10) * p
    }
}

/// The table's order: a column and which way, nil for the order heard.
struct NetSort: Equatable {
    var column: String
    var ascending: Bool
}
