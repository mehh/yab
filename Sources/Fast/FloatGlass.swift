import AppKit

/// A floating control group on the system's glass. Move, size and fade this
/// view; put its controls in `content`, so AppKit can keep them legible as
/// the material adapts. The picture itself stays outside the glass.
final class FloatGlass: NSView {
    let content: NSView
    private let material: NSView
    private let effects: NSView

    var cornerRadius: CGFloat {
        didSet { updateCorners() }
    }

    /// The same clear media material for video and call controls.
    static func media(cornerRadius: CGFloat) -> FloatGlass {
        FloatGlass(cornerRadius: cornerRadius, appearance: NSAppearance(named: .darkAqua), overVideo: true)
    }

    /// Semantic states tint the native material rather than covering it.
    var tintColor: NSColor? {
        didSet {
            guard tintColor != oldValue else { return }
            if #available(macOS 26.0, *), let glass = material as? NSGlassEffectView {
                glass.tintColor = tintColor
            } else {
                content.wantsLayer = true
                content.layer?.backgroundColor = (tintColor ?? .clear).cgColor
                content.layer?.cornerRadius = cornerRadius
                content.layer?.masksToBounds = true
            }
        }
    }

    var usesLiquidGlass: Bool {
        if #available(macOS 26.0, *) { return material is NSGlassEffectView }
        return false
    }

    /// Inherit the surrounding appearance by default. A group with fixed
    /// white layer marks can request Dark Aqua explicitly.
    init(frame: NSRect = .zero, cornerRadius: CGFloat = 18, appearance: NSAppearance? = nil,
         overVideo: Bool = false) {
        self.cornerRadius = cornerRadius
        let area = NSRect(origin: .zero, size: frame.size)
        let contents = NSView(frame: area)
        contents.autoresizingMask = [.width, .height]
        content = contents

        if #available(macOS 26.0, *), LiquidGlass.materialReady {
            let glass = NSGlassEffectView(frame: area)
            // Clear is the media overlay variant; its caller supplies the
            // dimming behind the glass and bright foreground marks.
            LiquidGlassMaterial.wear(overVideo ? .clear : .regular, on: glass)
            glass.contentView = contents
            glass.autoresizingMask = [.width, .height]
            material = glass

            let holder = NSView(frame: area)
            holder.autoresizingMask = [.width, .height]
            holder.addSubview(glass)
            let container = NSGlassEffectContainerView(frame: area)
            // Batch the material without distorting nearby control groups.
            container.spacing = 0
            container.contentView = holder
            effects = container
        } else {
            let plate = NSVisualEffectView(frame: area)
            plate.material = .popover
            plate.blendingMode = .withinWindow
            plate.state = .active
            plate.wantsLayer = true
            plate.layer?.cornerCurve = .continuous
            plate.layer?.masksToBounds = true
            plate.addSubview(contents)
            material = plate
            effects = plate
        }

        super.init(frame: frame)
        self.appearance = appearance
        effects.autoresizingMask = [.width, .height]
        addSubview(effects)
        updateCorners()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func updateCorners() {
        let radius = max(0, cornerRadius)
        if #available(macOS 26.0, *), let glass = material as? NSGlassEffectView {
            glass.cornerRadius = radius
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            material.layer?.cornerRadius = radius
            content.layer?.cornerRadius = radius
            CATransaction.commit()
        }
    }
}
