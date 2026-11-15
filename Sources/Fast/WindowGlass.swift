import AppKit

/// Native glass style writes: on some macOS 26 seeds the class is present
/// but instances do not answer `setStyle:` yet.
enum LiquidGlassMaterial {
    private static let styleSetter = NSSelectorFromString("setStyle:")

    static var present: Bool { LiquidGlass.materialReady }

    @available(macOS 26.0, *)
    static func wear(_ style: NSGlassEffectView.Style, on glass: NSGlassEffectView) {
        guard glass.responds(to: styleSetter) else { return }
        glass.style = style
    }
}

/// A resolved material, separate from the look's own glass step.
enum WindowGlassStyle: String {
    case off, clear, regular, opaque

    var active: Bool { self != .off }
    var usesLiquid: Bool { self == .clear || self == .regular }
}

/// The window frame as Liquid Glass: a space's look worn past the end of
/// its transparency (the wave's last step, LookSlider), its color kept on
/// the glass as a tint. Which glass goes by the color's side, as the
/// frosted window's veil does (BackdropVeil): a dark color is Clear glass
/// over a black veil, a light one Regular glass, which keeps itself light.
enum WindowGlassPolicy {
    /// The least of the black veil under a dark color: the desktop through
    /// Clear glass, kept readable over a white window behind.
    static let darkVeilOpacity: CGFloat = 0.58

    static var supported: Bool { LiquidGlassMaterial.present }

    static func resolve(enabled: Bool, dark: Bool, supported: Bool,
                        reduceTransparency: Bool, increaseContrast: Bool) -> WindowGlassStyle {
        guard enabled, supported else { return .off }
        guard !reduceTransparency, !increaseContrast else { return .opaque }
        return dark ? .clear : .regular
    }

    @MainActor static func current(enabled: Bool, dark: Bool) -> WindowGlassStyle {
        resolve(enabled: enabled, dark: dark, supported: supported,
                reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
    }

    /// How see-through the color lies on the glass, as a transparency
    /// (BackdropTransparency), so the window, a switch's wash and a card's
    /// frost all work it out as they do for a frosted window: a gray at
    /// half, a color at a third, the glass showing and the color still the
    /// space's.
    static func transparency(for color: NSColor) -> Double {
        color.oklch.1 < 0.02 ? 0.6 : 0.8
    }

    /// The black veil under a dark color on Clear glass: as much as the
    /// words need (muted, 4.5 to 1) over a white window behind, every end
    /// of a gradient counted, and never less than `darkVeilOpacity`. A
    /// color lighter than the veiled white would lift the ground the words
    /// stand on.
    static func veil(for colors: [NSColor], transparency: Double) -> CGFloat {
        let key = colors.map(\.hex).joined() + String(Int((transparency * 1000).rounded()))
        if let hit = kept[key] { return hit }
        let words = NSColor(white: 0.96, alpha: 1)
        let alpha = CGFloat(BackdropTransparency.opacity(transparency))
        var made = darkVeilOpacity
        while made < 1 {
            let under = NSColor.black.mixed(over: .white, made)
            if colors.allSatisfy({ words.contrast(with: $0.mixed(over: under, alpha)) >= 4.5 }) { break }
            made = min(1, made + 0.02)
        }
        if kept.count > 64 { kept.removeAll() }
        kept[key] = made
        return made
    }

    nonisolated(unsafe) private static var kept: [String: CGFloat] = [:]
}
