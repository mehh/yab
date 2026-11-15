import AppKit
import SwiftUI

/// Transparency leaves a little of the selected color on the glass.
/// It never changes the stored color or the strength of the native blur.
enum BackdropTransparency {
    static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }

    static func opacity(_ value: Double, reduced: Bool = false) -> Double {
        reduced ? 1 : 1 - 0.84 * clamp(value)
    }
}

struct WindowBackdrop: NSViewRepresentable {
    @Environment(Browser.self) private var browser: Browser?
    let color: Color
    let grain: Double
    let transparency: Double
    var colors: [Color] = []
    /// Liquid Glass under the color, the look's step past its transparency.
    var glass = false
    /// Drawings over the color (LookDrawings), and how strongly.
    var drawings: LookDrawings.Set? = nil
    var drawingsStrength: Double = 0
    /// How many steps the colors have turned (Shift with tabs, LookCard).
    var step: Int = 0

    func makeNSView(context: Context) -> WindowBackdropView {
        WindowBackdropView(frame: .zero)
    }

    func updateNSView(_ view: WindowBackdropView, context: Context) {
        view.bind(to: browser?.spaceWash)
        view.wear(SpaceWash.Paint(color: NSColor(color), grain: grain,
                                 colors: colors.map { NSColor($0) }, transparency: transparency, glass: glass,
                                 drawings: drawings, drawingsStrength: drawingsStrength))
        view.coating.turn(to: step)
    }

    static func dismantleNSView(_ view: WindowBackdropView, coordinator: ()) {
        view.bind(to: nil)
    }
}

final class WindowBackdropView: NSView {
    private weak var wash: SpaceWash?

    func bind(to wash: SpaceWash?) {
        guard self.wash !== wash else { return }
        if self.wash?.backdrop === self { self.wash?.backdrop = nil }
        self.wash = wash
        wash?.backdrop = self
    }

    let glass = NSVisualEffectView()
    /// Holds the frost on its color's side (BackdropVeil).
    let veiled = NSView(frame: .zero)
    let coating = BackdropCoatingView(frame: .zero)
    /// The drawings over the window's color (LookDrawings), above the
    /// coating rather than in it: the coating's alpha is the window's
    /// transparency, and drawings in it went with the color, gone at its
    /// most see-through.
    let drawings = BackdropDrawingsView(frame: .zero)
    private(set) var glassStyle: WindowGlassStyle = .off
    private var glassDark = false
    private var liquid: NSView?
    private var veil: NSView?
    private let rim = CALayer()
    private var cover: Float = 0
    private var paint: SpaceWash.Paint?
    private var displayObserver: NSObjectProtocol?
    /// How opaque the color laid over it (SpaceWash) is: under a
    /// see-through one it gives way as much as that color covers, so the
    /// glass shows through as the two together ask. Two opaque colors cross
    /// straight, as far as the row has gone: given way under an opaque one,
    /// the glass's gray came up between them halfway. Not said (a space's
    /// preview over it), as see-through as can be: it gives way as the
    /// cover comes, so the preview's own transparency shows the glass.
    var overOpacity: Float = 0 {
        didSet { if overOpacity != oldValue { frost() } }
    }

    /// The coating's opacity with `cover` of the other color over it.
    private func given(_ cover: Float, _ alpha: Float) -> Float {
        SpaceWash.given(cover, alpha: alpha, over: overOpacity)
    }
    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]
        coating.frame = bounds
        coating.autoresizingMask = [.width, .height]
        veiled.wantsLayer = true
        veiled.frame = bounds
        veiled.autoresizingMask = [.width, .height]
        drawings.frame = bounds
        drawings.autoresizingMask = [.width, .height]
        // Real sibling views keep the coating above AppKit's material.
        addSubview(glass)
        addSubview(veiled)
        addSubview(coating)
        addSubview(drawings)
        displayObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restyle() }
        }
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let displayObserver { NSWorkspace.shared.notificationCenter.removeObserver(displayObserver) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isOpaque = false
        window?.backgroundColor = .clear
        shapeGlass()
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
        veiled.frame = bounds
        coating.frame = bounds
        drawings.frame = bounds
        liquid?.frame = bounds
        veil?.frame = bounds
        shapeGlass()
    }

    func wear(_ paint: SpaceWash.Paint) {
        // The same paint again (the window's body ran for another tab of
        // the same color): nothing to do, unless a space's color is being
        // put on over it.
        if Narrow.leaves, paint == self.paint, wash?.turning != true { return }
        self.paint = paint
        restyle()
    }

    /// The material for the paint worn: Liquid Glass while its look asks
    /// for it and the Mac can, Clear or Regular by its color's side.
    private func restyle() {
        guard let paint else { return }
        let dark = BackdropVeil.dark(paint.color)
        let style = WindowGlassPolicy.current(enabled: paint.glass, dark: dark)
        if style != glassStyle || (style.active && dark != glassDark) {
            applyGlass(style: style, dark: dark)
        } else {
            refreshPaint()
        }
    }

    var glassReport: [String: Any] {
        let frame: (NSView) -> [Double] = { view in
            [Double(view.frame.minX), Double(view.frame.minY), Double(view.frame.width), Double(view.frame.height)]
        }
        return [
            "style": glassStyle.rawValue,
            "glass": paint?.glass ?? false,
            "dark": glassDark,
            "liquidClass": liquid.map { NSStringFromClass(type(of: $0)) } ?? "",
            "liquidVisible": liquid.map { !$0.isHiddenOrHasHiddenAncestor } ?? false,
            "coatingVisible": !coating.isHiddenOrHasHiddenAncestor,
            "hudVisible": !glass.isHiddenOrHasHiddenAncestor,
            "veilOpacity": veil?.isHidden == false ? Double(veil?.layer?.backgroundColor?.alpha ?? 0) : 0,
            "liquidFrame": liquid.map(frame) ?? [],
            "coatingFrame": frame(coating),
            "bounds": [Double(bounds.width), Double(bounds.height)],
            "window": window?.windowNumber ?? -1
        ]
    }

    /// Material changes are applied before the old material is hidden.
    /// Kept separate from policy so transitions can be checked deterministically.
    func applyGlass(style requested: WindowGlassStyle, dark: Bool) {
        var style = requested
        if style.active {
            if #available(macOS 26.0, *), LiquidGlassMaterial.present {} else { style = .off }
        }
        if style.usesLiquid, #available(macOS 26.0, *), LiquidGlassMaterial.present {
            let material: NSGlassEffectView
            if let existing = liquid as? NSGlassEffectView {
                material = existing
            } else {
                material = NSGlassEffectView(frame: bounds)
                material.autoresizingMask = [.width, .height]
                material.setAccessibilityElement(false)
                addSubview(material, positioned: .above, relativeTo: glass)
                liquid = material
            }
            LiquidGlassMaterial.wear(style == .clear ? .clear : .regular, on: material)
            material.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            if veil == nil {
                let made = NSView(frame: bounds)
                made.wantsLayer = true
                made.autoresizingMask = [.width, .height]
                made.setAccessibilityElement(false)
                addSubview(made, positioned: .above, relativeTo: material)
                veil = made
            }
            veil?.isHidden = style != .clear
            veil?.layer?.backgroundColor = NSColor.black.withAlphaComponent(WindowGlassPolicy.darkVeilOpacity).cgColor
        } else {
            liquid?.removeFromSuperview()
            liquid = nil
            veil?.removeFromSuperview()
            veil = nil
        }
        glassStyle = style
        glassDark = dark
        if style.active {
            rim.borderWidth = 1
            rim.cornerCurve = .continuous
            rim.borderColor = (dark ? NSColor.white.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.12)).cgColor
            if rim.superlayer == nil { layer?.addSublayer(rim) }
        } else {
            rim.removeFromSuperlayer()
        }
        shapeGlass()
        refreshPaint()
    }

    /// The paint as drawn: on glass as worn, its color a tint; where the Mac
    /// asks for less transparency or more contrast, the color whole.
    private var effectivePaint: SpaceWash.Paint? {
        guard var paint else { return nil }
        if glassStyle == .opaque { paint.transparency = 0 }
        return paint
    }

    /// Whether the frost behind the window shows anywhere: not under
    /// Liquid Glass, nor where the Mac asks for less transparency, nor
    /// under an opaque color with nothing see-through coming over it (no
    /// transparency, the look's default). Covered, it was still worked
    /// out: the window server blurred what is behind the whole window
    /// again on every frame the window drew, 60 a second under a page
    /// that animates (a WebGL scene, #911).
    private var frosted: Bool {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        if glassStyle.active || reduced { return false }
        guard let paint = effectivePaint else { return true }
        if BackdropTransparency.opacity(paint.transparency) < 1 { return true }
        // A see-through space's color coming over, or still clearing: the
        // coating gives way under it (`given`), and the frost shows there.
        return overOpacity < 1 && (cover > 0 || coating.layer?.animation(forKey: "space-cover") != nil)
    }

    /// The frost shown or hidden as `frosted` says.
    private func frost() {
        let hidden = !frosted
        if glass.isHidden != hidden { glass.isHidden = hidden }
        if veiled.isHidden != hidden { veiled.isHidden = hidden }
    }

    private func refreshPaint() {
        frost()
        glass.alphaValue = 1
        if let paint = effectivePaint {
            // Clear glass's veil, as much as the words on this color need.
            if glassStyle == .clear, let layer = veil?.layer {
                let opacity = WindowGlassPolicy.veil(for: [paint.color] + paint.colors, transparency: paint.transparency)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.backgroundColor = NSColor.black.withAlphaComponent(opacity).cgColor
                CATransaction.commit()
            }
            var plain = paint
            plain.drawings = nil
            coating.wear(plain)
            drawings.wear(paint)
            if !glass.isHidden {
                let side = BackdropVeil.appearance(for: paint.color)
                if glass.appearance?.name != side?.name { glass.appearance = side }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                veiled.layer?.backgroundColor = BackdropVeil.veil(for: paint.color).cgColor
                CATransaction.commit()
            }
        }
        setCover(cover)
    }

    private static let glassMask: NSImage = {
        let corner = Radius.window
        let side = corner * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: corner, left: corner, bottom: corner, right: corner)
        image.resizingMode = .stretch
        return image
    }()

    /// Mask the native material itself: clipping a parent can flatten
    /// a behind-window effect. Fullscreen uses the window's square contour.
    private func shapeGlass() {
        let fullscreen = window?.styleMask.contains(.fullScreen) == true
        let corner: CGFloat = glassStyle.active && !fullscreen ? Radius.window : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glass.maskImage = glassStyle.active && corner > 0 ? Self.glassMask : nil
        veil?.layer?.cornerRadius = corner
        veil?.layer?.cornerCurve = .continuous
        // The color lies on the glass in the glass's own outline.
        for layer in [coating.layer, drawings.layer] {
            layer?.cornerRadius = glassStyle.active ? corner : 0
            layer?.cornerCurve = .continuous
            layer?.masksToBounds = glassStyle.active && corner > 0
        }
        rim.frame = bounds
        rim.cornerRadius = corner
        rim.isHidden = !glassStyle.active || fullscreen
        if #available(macOS 26.0, *), let material = liquid as? NSGlassEffectView {
            material.cornerRadius = corner
        }
        CATransaction.commit()
    }

    /// The cover on the spring the column's spaces land on (SpacePager).
    /// `began` and `velocity`: the row's spring, set off then and that
    /// fast (SpaceWash.clear, go).
    func setCover(_ value: Float, from: Float, spring: Bool, began: CFTimeInterval? = nil, velocity: CGFloat = 0) {
        cover = value
        guard let layer = coating.layer, let paint = effectivePaint else { return }
        let alpha = Float(BackdropTransparency.opacity(paint.transparency,
                                    reduced: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency))
        CATransaction.begin()
        // Set first: it covers only the animations added after it.
        CATransaction.setCompletionBlock { [weak self] in MainActor.assumeIsolated { self?.frost() } }
        CATransaction.setDisableActions(true)
        layer.opacity = given(value, alpha)
        layer.add(SpaceWash.since(began, SpaceWash.coverAnimation(alpha: alpha, over: overOpacity, from: from, to: value, velocity: velocity), in: layer),
                  forKey: "space-cover")
        frost()
        CATransaction.commit()
    }

    /// A space preview replaces the underlying coating, so its transparent
    /// color can still see the glass instead of the old opaque space.
    func setCover(_ value: Float, from: Float? = nil,
                  duration: CFTimeInterval = 0, timing: CAMediaTimingFunction? = nil) {
        cover = value
        guard let layer = coating.layer, let paint = effectivePaint else { return }
        let alpha = Float(BackdropTransparency.opacity(paint.transparency,
                                    reduced: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency))
        CATransaction.begin()
        // Set first: it covers only the animations added after it.
        CATransaction.setCompletionBlock { [weak self] in MainActor.assumeIsolated { self?.frost() } }
        CATransaction.setDisableActions(true)
        layer.opacity = given(value, alpha)
        if let from, duration > 0 {
            layer.add(SpaceWash.coverAnimation(alpha: alpha, over: overOpacity, from: from, to: value, duration: duration, timing: timing),
                      forKey: "space-cover")
        } else {
            layer.removeAnimation(forKey: "space-cover")
        }
        frost()
        CATransaction.commit()
    }
}

/// Color, gradient and grain share one alpha; text and pages sit above it.
final class BackdropCoatingView: NSView {
    let gradient = CAGradientLayer()
    /// Drawings over the color, under the grain (LookDrawings).
    let drawings = CALayer()
    let grain = CALayer()
    /// How many steps the gradient has turned, a quarter of the way round
    /// the window each (Shift with tabs).
    private(set) var step = 0
    /// Its layer has y the other way up from the window's backdrop's (a
    /// ground in SwiftUI, CardGroundView): the ends mirrored top to bottom,
    /// so a column edge to edge turns its colors the way the window does.
    var upsideDown = false {
        didSet {
            guard upsideDown != oldValue else { return }
            let ends = self.ends(step)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            gradient.startPoint = ends.start
            gradient.endPoint = ends.end
            CATransaction.commit()
        }
    }
    /// What the drawings layer wears now, so it is drawn again only when
    /// the set or the ink changes.
    private var drawn: String?
    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let ends = Self.ends(0)
        gradient.startPoint = ends.start
        gradient.endPoint = ends.end
        layer?.addSublayer(gradient)
        drawings.isHidden = true
        layer?.addSublayer(drawings)
        grain.backgroundColor = NSColor(patternImage: Grain.tile).cgColor
        layer?.addSublayer(grain)
    }

    /// Where the gradient starts and ends after `step` turns: from the top
    /// leading corner round by quarters, so its colors trade places the way
    /// a wheel turns, through the sides, never jumping across.
    nonisolated static func ends(_ step: Int) -> (start: CGPoint, end: CGPoint) {
        let corners = [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)]
        let at = ((step % 4) + 4) % 4
        return (corners[at], corners[(at + 2) % 4])
    }

    private func ends(_ step: Int) -> (start: CGPoint, end: CGPoint) {
        let ends = Self.ends(step)
        guard upsideDown else { return ends }
        return (CGPoint(x: ends.start.x, y: 1 - ends.start.y), CGPoint(x: ends.end.x, y: 1 - ends.end.y))
    }

    /// The colors turned to `step`, a quarter turn over a little over half
    /// a second from where they were; at once with Reduce Motion.
    func turn(to step: Int) {
        guard step != self.step else { return }
        let from = ends(self.step), to = ends(step)
        self.step = step
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.startPoint = to.start
        gradient.endPoint = to.end
        CATransaction.commit()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, !gradient.isHidden else { return }
        for (key, a, b) in [("startPoint", from.start, to.start), ("endPoint", from.end, to.end)] {
            let move = CABasicAnimation(keyPath: key)
            move.fromValue = NSValue(point: a)
            move.toValue = NSValue(point: b)
            move.duration = 0.56
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            gradient.add(move, forKey: "look-turn-" + key)
        }
    }

    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        drawings.frame = bounds
        grain.frame = bounds
        CATransaction.commit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        drawings.frame = bounds
        grain.frame = bounds
        CATransaction.commit()
    }

    func wear(_ paint: SpaceWash.Paint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.isHidden = paint.colors.isEmpty
        gradient.colors = ([paint.color] + paint.colors).map(\.cgColor)
        layer?.backgroundColor = paint.colors.isEmpty ? paint.color.cgColor : nil
        grain.isHidden = paint.grain <= 0
        grain.opacity = Float(Grain.opacity(paint.grain))
        LookDrawings.dress(drawings, with: paint, drawn: &drawn)
        layer?.opacity = Float(BackdropTransparency.opacity(paint.transparency,
                                       reduced: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency))
        CATransaction.commit()
    }
}

/// Drawings over the window's color, at their own strength whatever the
/// window's transparency (LookDrawings).
final class BackdropDrawingsView: NSView {
    let pattern = CALayer()
    private var drawn: String?
    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        pattern.isHidden = true
        layer?.addSublayer(pattern)
    }

    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pattern.frame = bounds
        CATransaction.commit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pattern.frame = bounds
        CATransaction.commit()
    }

    func wear(_ paint: SpaceWash.Paint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        LookDrawings.dress(pattern, with: paint, drawn: &drawn)
        CATransaction.commit()
    }
}
