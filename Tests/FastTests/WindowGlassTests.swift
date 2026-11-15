import AppKit
import Testing
import SwiftUI
@testable import Fast

@Suite(.serialized)
struct WindowGlassTests {
    @Test func supportedTracksNativeGlassAvailability() {
        #expect(WindowGlassPolicy.supported == LiquidGlass.materialReady)
    }

    @Test func disabledOrUnsupportedNeverCreatesAHoleInTheWindow() {
        for dark in [false, true] {
            for reduced in [false, true] {
                for contrast in [false, true] {
                    #expect(WindowGlassPolicy.resolve(enabled: false, dark: dark, supported: true,
                                                      reduceTransparency: reduced, increaseContrast: contrast) == .off)
                    #expect(WindowGlassPolicy.resolve(enabled: true, dark: dark, supported: false,
                                                      reduceTransparency: reduced, increaseContrast: contrast) == .off)
                }
            }
        }
    }

    @Test func accessibilityAlwaysGetsASolidGround() {
        for dark in [false, true] {
            for pair in [(true, false), (false, true), (true, true)] {
                let style = WindowGlassPolicy.resolve(enabled: true, dark: dark, supported: true,
                                                     reduceTransparency: pair.0, increaseContrast: pair.1)
                #expect(style == .opaque)
                #expect(style.active && !style.usesLiquid)
            }
        }
        #expect(WindowGlassPolicy.resolve(enabled: true, dark: true, supported: true,
                                          reduceTransparency: false, increaseContrast: false) == .clear)
        #expect(WindowGlassPolicy.resolve(enabled: true, dark: false, supported: true,
                                          reduceTransparency: false, increaseContrast: false) == .regular)
    }

    @MainActor @Test func darkVeilDesignValuesProtectSecondaryInkOverAWhiteBacking() throws {
        // This calculation checks the chosen palette and fixed sRGB veil.
        // WindowServer composition still requires separate native captures.
        let channel = 1 - Double(WindowGlassPolicy.darkVeilOpacity)
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let tone = Tone(NSColor(white: 0.12, alpha: 1), lifted: true, glass: true)
        func contrast(_ ink: Color) throws -> Double {
            // The words on glass are let through: what shows is them over
            // the backing.
            let drawn = try #require(NSColor(ink).usingColorSpace(.sRGB))
            let rgb = drawn.withAlphaComponent(1).mixed(over: NSColor(white: CGFloat(channel), alpha: 1), drawn.alphaComponent)
            let luminance = 0.2126 * linear(Double(rgb.redComponent))
                + 0.7152 * linear(Double(rgb.greenComponent))
                + 0.0722 * linear(Double(rgb.blueComponent))
            #expect(rgb.alphaComponent == 1)
            return (luminance + 0.05) / (linear(channel) + 0.05)
        }
        // Text people read holds 4.5 over the worst backing.
        for ink in [Palette.muted(on: tone), Palette.strong(on: tone)] {
            #expect(try contrast(ink) >= 4.5)
        }
        // Faint is the quiet tier (the new tab's words, 42e9d9d3): it stays
        // visibly lighter than the veiled white, and quieter than muted.
        let faint = try contrast(Palette.faint(on: tone))
        #expect(faint >= 1.5)
        #expect(faint < (try contrast(Palette.muted(on: tone))))
    }

    /// A look on glass keeps its color as a tint, and the black veil under a
    /// dark one grows as far as the words need over a white window behind,
    /// for every preset as a dark window wears it.
    @MainActor @Test func everyDarkTintKeepsMutedWordsReadableOverWhite() throws {
        let presets = LookPresets.pages.flatMap(\.presets).map(\.main) + ["FFFFFF", "000000"]
        for hex in presets {
            let color = try #require(NSColor(hex: hex)).deepened
            #expect(BackdropVeil.dark(color), "deepened \(hex) is on the dark side")
            let tint = WindowGlassPolicy.transparency(for: color)
            let veil = WindowGlassPolicy.veil(for: [color], transparency: tint)
            #expect(veil >= WindowGlassPolicy.darkVeilOpacity && veil <= 1)
            let ground = color.mixed(over: NSColor.black.mixed(over: .white, veil), CGFloat(BackdropTransparency.opacity(tint)))
            let ink = try #require(NSColor(Palette.muted(on: Tone(color, lifted: true, glass: true))).usingColorSpace(.sRGB))
            let muted = ink.withAlphaComponent(1).mixed(over: ground, ink.alphaComponent)
            #expect(muted.contrast(with: ground) >= 4.5, "\(hex)")
        }
        // A gray lies on the glass at half, a color at a third.
        #expect(WindowGlassPolicy.transparency(for: NSColor(white: 0.4, alpha: 1)) == 0.6)
        #expect(WindowGlassPolicy.transparency(for: try #require(NSColor(hex: "E54C6E"))) == 0.8)
    }

    @MainActor @Test func defaultViewRetainsTheExistingMaterialAndSubviewOrder() {
        _ = NSApplication.shared
        let view = WindowBackdropView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        #expect(view.glassStyle == .off)
        #expect(view.subviews.count == 4)
        #expect(view.subviews[0] === view.glass)
        #expect(view.subviews[1] === view.veiled)
        #expect(view.subviews[2] === view.coating)
        #expect(view.subviews[3] === view.drawings)
        #expect(view.glass.material == .hudWindow)
        #expect(view.hitTest(.zero) == nil)
    }

    @MainActor @Test func glassKeepsTheColorAsATintAndLeavingRestoresTheSavedPaint() throws {
        guard #available(macOS 26.0, *) else { return }
        // The Mac's own accessibility settings make it solid instead.
        guard WindowGlassPolicy.current(enabled: true, dark: true) == .clear else { return }
        _ = NSApplication.shared
        let view = WindowBackdropView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let saved = SpaceWash.Paint(color: .red, grain: 0.4, colors: [.blue], transparency: 0.7)
        view.wear(saved)
        #expect(view.glassStyle == .off)
        let stops = try #require(view.coating.gradient.colors as? [CGColor])

        // The same space on glass: Clear glass for a dark color, the color on it.
        let plum = NSColor(srgbRed: 0.22, green: 0.12, blue: 0.3, alpha: 1)
        let tint = WindowGlassPolicy.transparency(for: plum)
        view.wear(SpaceWash.Paint(color: plum, grain: 0.4, transparency: tint, glass: true))
        let native = try #require(view.subviews.compactMap { $0 as? NSGlassEffectView }.first)
        #expect(view.glassStyle == .clear)
        #expect(native.style == .clear && !native.isHidden)
        #expect(view.glass.isHidden && !view.coating.isHidden)
        let coated = try #require(view.coating.layer)
        #expect(abs(Double(coated.opacity) - BackdropTransparency.opacity(tint)) < 0.00001)
        #expect(coated.backgroundColor == plum.cgColor)
        #expect(view.glassReport["glass"] as? Bool == true)
        #expect(view.glassReport["liquidClass"] as? String == "NSGlassEffectView")
        #expect((view.glassReport["veilOpacity"] as? Double ?? 0) >= Double(WindowGlassPolicy.darkVeilOpacity))
        #expect(view.hitTest(NSPoint(x: 20, y: 20)) == nil)

        // A light color: Regular glass, no veil.
        let milk = NSColor(white: 0.92, alpha: 1)
        view.wear(SpaceWash.Paint(color: milk, grain: 0, transparency: WindowGlassPolicy.transparency(for: milk), glass: true))
        #expect(view.subviews.compactMap { $0 as? NSGlassEffectView }.first === native)
        #expect(view.glassStyle == .regular && native.style == .regular)
        #expect((view.glassReport["veilOpacity"] as? NSNumber)?.doubleValue == 0)

        view.wear(saved)
        #expect(view.glassStyle == .off)
        #expect(view.subviews.count == 4)
        #expect(view.subviews[0] === view.glass && view.subviews[1] === view.veiled
                && view.subviews[2] === view.coating && view.subviews[3] === view.drawings)
        #expect(!view.coating.isHidden)
        #expect(view.coating.gradient.colors as? [CGColor] == stops)
        #expect(!view.coating.grain.isHidden)
        let expected = BackdropTransparency.opacity(saved.transparency,
                                                   reduced: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        let restoredLayer = try #require(view.coating.layer)
        #expect(abs(Double(restoredLayer.opacity) - expected) < 0.00001)
        #expect(view.glass.maskImage == nil)
    }

    @MainActor @Test func solidFallbackWearsTheColorWhole() throws {
        guard #available(macOS 26.0, *) else { return }
        _ = NSApplication.shared
        let view = WindowBackdropView(frame: .zero)
        view.wear(SpaceWash.Paint(color: .red, grain: 1, colors: [.blue], transparency: 0.8, glass: true))
        view.applyGlass(style: .opaque, dark: true)
        let layer = try #require(view.coating.layer)
        #expect(view.subviews.count == 4)
        #expect(view.glass.isHidden && !view.coating.isHidden)
        #expect(layer.opacity == 1)
        #expect(!view.coating.gradient.isHidden)
    }

    @MainActor @Test func floatingColumnOnGlassIsAFrostedCardInTheSpacesColor() throws {
        try #require(Store.testing)
        let prefs = Preferences()
        let saved = SpacePaint(prefs)
        let savedMode = prefs.backdrop
        defer {
            saved.wear(prefs)
            prefs.backdrop = savedMode
        }
        prefs.backdrop = .color
        prefs.swatch = .custom
        prefs.backdropColor = .red
        prefs.grain = 1
        prefs.backdropTransparency = 0.3
        prefs.backdropColors = ["0000FF"]
        prefs.lookGlass = true
        let paint = try #require(SpaceWash.worn(prefs))
        #expect(paint.glass == WindowGlassPolicy.supported)
        #expect(paint.transparency == (WindowGlassPolicy.supported ? WindowGlassPolicy.transparency(for: paint.color) : 0.3))
        #expect(paint.grain == 1 && paint.colors.count == 1)
        // Its words: the glass's own on the docked column, a card's deep
        // shades on the column brought out over the page.
        let tone = Tone(paint.color, lifted: true, glass: prefs.wearsGlass)
        #expect(Column.paint(tone, prefs: prefs) == paint)
        let card = tone.card(paint)
        #expect(!card.glass)
        #expect(card.seeThrough == !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        // The transparency is kept for the way back off the glass.
        prefs.lookGlass = false
        #expect(SpacePaint(prefs).transparency == 0.3 && !SpacePaint(prefs).glass)
        #expect(SpaceWash.worn(prefs)?.transparency == 0.3)
    }

    @MainActor @Test func resizeUpdatesTheNativeMaterialFrameAndContour() throws {
        guard #available(macOS 26.0, *), LiquidGlass.materialReady else { return }
        _ = NSApplication.shared
        let view = WindowBackdropView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.applyGlass(style: .clear, dark: true)
        let native = try #require(view.subviews.compactMap { $0 as? NSGlassEffectView }.first)
        #expect(native.cornerRadius == Radius.window)
        window.setContentSize(NSSize(width: 800, height: 500))
        view.layoutSubtreeIfNeeded()
        #expect(native.frame == view.bounds)
        #expect(view.subviews.allSatisfy { $0.frame == view.bounds })
        #expect(native.cornerRadius == Radius.window)
        window.contentView = nil
    }
}
