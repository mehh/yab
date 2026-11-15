# Launch crash on macOS 26 when window Liquid Glass applies `setStyle:`

## Summary

Yab aborts a second or two after launch on macOS 26.0 (25A5316i). The main window is laying out; native Liquid Glass on the window backdrop sends `setStyle:` to an object that does not implement it.

## Environment

- Yab 0.47.10 (build 202611102135), bundle `dev.serafim.fast`
- macOS 26.0 (25A5316i)
- Mac16,8 (Apple Silicon)

## Steps to reproduce

1. Install or open Yab on the Mac above (default window look with Liquid Glass is enough).
2. Launch the app.
3. Wait about 1.5 seconds.

## Expected behavior

The browser window opens and stays running.

## Actual behavior

Yab crashes with `SIGABRT` on the main thread.

## Crash signature

```
NSInvalidArgumentException: -[(dynamic class) setStyle:]: unrecognized selector sent to instance
```

Thrown while an `NSViewRepresentable` creates or updates its AppKit view (`PlatformViewRepresentableAdaptor.makeViewProvider`), inside `NSHostingView.layout()`. Up the stack: `GeometryReader`, a closure using `GeometryProxy.frame(in:)`, and a `ZStack` in the main window body.

## Backtrace (trimmed)

```
0   CoreFoundation    __exceptionPreprocess
1   libobjc.A.dylib     objc_exception_throw
2   CoreFoundation    -[NSObject(NSObject) doesNotRecognizeSelector:]
3   CoreFoundation    ___forwarding___
4   CoreFoundation    _CF_forwarding_prep_0
5–8 yab               (WindowBackdrop / main window layout)
9   SwiftUI           PlatformViewRepresentableAdaptor.makeViewProvider(context:)
10  SwiftUI           NSHostingView.layout()
```

## Root cause

Window Liquid Glass was enabled whenever `#available(macOS 26.0, *)` was true. On this seed, `NSGlassEffectView` is named in the SDK but instances do not respond to `setStyle:`. The first failing write at launch is the window backdrop applying clear or regular glass:

- [`Sources/Fast/WindowBackdrop.swift` line 205](https://github.com/yetanotherbrowser/yab/blob/main/Sources/Fast/WindowBackdrop.swift#L205) (`material.style = …` in `WindowBackdropView.applyGlass`)
- Policy and SwiftUI gates had the same OS-only check: [`WindowGlassPolicy.supported`](https://github.com/yetanotherbrowser/yab/blob/main/Sources/Fast/WindowGlass.swift#L21-L24) and [`LiquidGlass.wanted`](https://github.com/yetanotherbrowser/yab/blob/main/Sources/YabDesign/Design.swift#L586-L590)

The same unguarded `material.style` / `glass.style` pattern exists in [`FloatGlass.swift`](https://github.com/yetanotherbrowser/yab/blob/main/Sources/Fast/FloatGlass.swift#L54) and [`PlayerBand.swift`](https://github.com/yetanotherbrowser/yab/blob/main/Sources/Fast/PlayerBand.swift#L199) (`IslandGlass.drop`).

## Frequency

Every launch on this OS build (for me).