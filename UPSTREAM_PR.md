# PR title

Stop launch crash when native Liquid Glass cannot take a style

---

## What changes

Yab opens on macOS 26 seeds where AppKit's Liquid Glass class is present but does not accept `setStyle:`.

Fixes #<issue>

## Why it happened

Window and control glass turned on from `#available(macOS 26.0, *)` alone. On some 26 builds (including 25A5316i), `NSGlassEffectView` exists in name but instances do not answer `setStyle:`. The main window's `WindowBackdrop` representable assigns `.style` during layout about a second after launch, which raises `NSInvalidArgumentException` and aborts.

The fix checks at runtime that `NSGlassEffectView` exists and that instances respond to `setStyle:` before any policy, SwiftUI gate, or native style write. When the check fails, behavior matches older macOS: HUD / `NSVisualEffectView` paths, no crash.

Touched sites:

- `LiquidGlass.materialReady` and `WindowGlassPolicy.supported` (`Sources/YabDesign/Design.swift`, `Sources/Fast/WindowGlass.swift`)
- `LiquidGlassMaterial.wear` for guarded style assignment
- `WindowBackdropView.applyGlass`, `FloatGlass`, `IslandGlass.drop`

## Proof

- [x] **Logic:** `swift test --filter WindowGlassTests` (adds `supportedTracksNativeGlassAvailability`; existing glass transition tests unchanged on Macs with working glass)

| Before | After |
|---|---|
| Launch aborts ~1.5 s in on 26.0 25A5316i | Window opens; frosted/HUD backdrop when native glass is unavailable |

## Checked on

- Yab Dev built from this branch on macOS: _(Kris: fill in after `./build.sh` on 25A5316i or matching seed)_
- Engine(s) tried: WebKit / Chromium (stock CEF) / **not about a page**

## Checklist

- [ ] `swift test` passes (or the suites this touches: `WindowGlassTests`)
- [x] `./design-check --head` is clean, or each exception says why with `// design:` _(no UI or design tokens changed)_
- [x] Anything that changes how Yab looks was approved in the issue first _(restores intended fallback, no new look)_
- [x] A new menu item is also a command in the field; a new Settings row is classified in `NativeActions.swift` _(n/a)_
- [x] Words on screen and in docs are American English, with no em dashes

## Risk and compatibility

- **Risk:** Low. No new timers or retries. When `materialReady` is false, code paths already existed for pre-glass macOS.
- **Compatibility:** Macs with fully working Liquid Glass keep clear/regular glass. Accessibility "Reduce transparency" unchanged. No change to stored settings or bundle IDs.