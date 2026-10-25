# SwiftGodotKit: crash when a GodotAppView is removed and shown again

This is a minimal iOS app that reproduces a SwiftGodotKit crash. The app keeps one `GodotApp` for its whole lifetime. If you remove that app's `GodotAppView` from the SwiftUI tree and then mount a new one for the same `GodotApp`, the app crashes. It crashes on the iOS Simulator (OpenGL) and on a device (Metal).

## How to run

You need Xcode 26.4 or later (tested with 26.4.1) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

1. Generate the project and build it. On the simulator:

   ```sh
   cd ios
   xcodegen
   xcodebuild -project SGKRepro.xcodeproj -scheme SGKRepro \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
     -derivedDataPath .build -skipMacroValidation -skipPackagePluginValidation build
   xcrun simctl boot 'iPhone 17 Pro'
   xcrun simctl install booted .build/Build/Products/Debug-iphonesimulator/SGKRepro.app
   xcrun simctl launch --console-pty booted com.example.sgkrepro -autoToggle 6
   ```

   For a device, use your team's development signing. You can pick your team in Xcode under Signing & Capabilities, or pass `DEVELOPMENT_TEAM=<your team ID>` and `-allowProvisioningUpdates` to `xcodebuild`. The app needs no capabilities. Change `PRODUCT_BUNDLE_IDENTIFIER` in `ios/project.yml` if your team needs its own prefix.
2. Tap **Show game**, then **Hide game**, then **Show game**. Or launch with `-autoToggle 6`, which toggles every 2 s and logs each toggle. The app crashes on the second **Show game** (`repro: toggle 3, game view mounted`).

`ios/game.pck` is committed. To rebuild it from `godot/`, run `GODOT=/path/to/Godot ./make-pck.sh` with the official Godot 4.7.2-stable editor. A pack-only export doesn't need export templates.

## Related: SwiftGodotKit #50

[#50](https://github.com/migueldeicaza/SwiftGodotKit/issues/50), "Crash on Re-entering Screen Containing Godot UI After Navigating Away", describes the same scenario from a user's point of view: you leave a screen that has a Godot view, then come back to it.

- **What's reported there:** apps create a new `GodotApp` for each visit, and they hit "Only one Godot Instance may be created" or "Wrapped.handle was nil". One comment there suggests keeping a single, app-wide engine instance instead.
- **What this repro shows:** keeping a single engine isn't enough. It keeps one `GodotApp` and re-creates only the `GodotAppView`, and it still crashes. On the simulator the crash is in the renderer; on a device it's in the display server.
- **So the cause here is narrower:** the view's rendering surface, not the engine's lifetime.

## What happens

The crash happens when the second view is mounted; removing the first view doesn't crash.

- **iOS Simulator (OpenGL ES 3, `gl_compatibility`):** the crash happens in the first frame the engine draws after the second mount. It's an `EXC_BAD_ACCESS` at `0x0` in `RasterizerCanvasGLES3::_render_items`.
- **iPad (Metal, `mobile`):** the crash happens earlier, while SwiftUI inserts the second view (in its `didMoveToSuperview`) and before any frame is drawn. It's an `EXC_BAD_ACCESS` in `objc_retain`, called from `DisplayServerAppleEmbedded::window_get_size` through `_get_layer_from_native_surface`.

It crashed in every run: 6 of 6 on the simulator and 5 of 5 on the iPad.

## The app

This is all of the Swift (`ios/Sources/ReproApp.swift`). The rest of the project is `ios/project.yml` and the one-scene Godot project in `godot/`. That scene is a `Node2D` with a rotating `Polygon2D` and a label showing the frame count.

```swift
import SwiftGodotKit
import SwiftUI

// One GodotApp for the app's lifetime. The button (or `-autoToggle <n>`, every 2 s)
// removes GodotAppView from the SwiftUI tree and mounts a new one for the same GodotApp.
@main
struct ReproApp: App {
    let godotApp = GodotApp(packFile: "game.pck")

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.godotApp, godotApp)
        }
    }
}

struct ContentView: View {
    @State private var showsGame = false
    @State private var toggles = 0

    var body: some View {
        VStack {
            Button(showsGame ? "Hide game" : "Show game", action: toggle)
                .buttonStyle(.borderedProminent)
            if showsGame {
                GodotAppView()
            } else {
                Color.gray.overlay { Text("Game view removed") }
            }
        }
        .task {
            let count = UserDefaults.standard.integer(forKey: "autoToggle")
            for _ in 0..<count {
                try? await Task.sleep(for: .seconds(2))
                toggle()
            }
            if count > 0 { NSLog("repro: finished %d toggles without crashing", count) }
        }
    }

    private func toggle() {
        showsGame.toggle()
        toggles += 1
        NSLog("repro: toggle %d, game view %@", toggles, showsGame ? "mounted" : "removed")
    }
}
```

## Expected behavior

The second `GodotAppView` attaches to the running engine and shows the scene again, as the first one did. If a `GodotApp` can only ever have one view, the app should get a documented error, not a crash.

## Actual behavior

### iOS Simulator: OpenGL ES 3 (`opengl3` / `gl_compatibility`)

The crash is `EXC_BAD_ACCESS (SIGSEGV)`, `KERN_INVALID_ADDRESS at 0x0000000000000000`. It happens on the main thread within about 0.2 s of the second mount. Here is the crashing thread:

```
0  libsystem_platform.dylib  _platform_memmove + 208
1  SGKRepro                  RasterizerCanvasGLES3::_render_items(...) + 1276
2  SGKRepro                  RasterizerCanvasGLES3::canvas_render_items(...) + 3736
3  SGKRepro                  RendererCanvasCull::_render_canvas_item_tree(...) + 612
4  SGKRepro                  RendererCanvasCull::render_canvas(...) + 196
5  SGKRepro                  RendererViewport::_draw_viewport(...) + 6808
6  SGKRepro                  RendererViewport::draw_viewports(...) + 1528
7  SGKRepro                  RenderingServerDefault::_draw(...) + 396
8  SGKRepro                  Main::iteration(...) + 1248
9  SGKRepro                  MethodBindTR<bool>::ptrcall(...) const + 40
10 SwiftGodot                GodotInstance.start() + 260
11 SGKRepro                  UIGodotAppView.iterate() + 528        (iOS-GodotAppView.swift:373)
12 SGKRepro                  @objc UIGodotAppView.iterate() + 44
13 QuartzCore                CA::Display::DisplayLinkItem::dispatch_(...) + 56
14 QuartzCore                CA::Display::DisplayLink::dispatch_items(...) + 804
15 QuartzCore                CA::Display::DisplayLink::dispatch_deferred_display_links(...) + 340
```

- **Frame 10** is in SwiftGodot's prebuilt binary, which labels it `GodotInstance.start()`. The call comes from frame 11 at line 373, which is `instance.iteration()` inside `iterate()`.
- **The other runs:** all six simulator crash reports have the same top frames.

### iPad: Metal (`metal` / `mobile`)

The crash is `EXC_BAD_ACCESS (SIGSEGV)`, `KERN_INVALID_ADDRESS` at an unmapped address that isn't null. In this report it's `0x0000000e2d10d8c0`. It happens synchronously, while SwiftUI inserts the second view.

- **The address differs from run to run.** In one run the fault was in `objc_msgSend` instead of `objc_retain`, and the report flagged a "possible pointer authentication failure".
- **The other frames match.** All five reports have frames 1 to 7 and 19 to 21 below.

```
0  libobjc.A.dylib           objc_retain + 16
1  SGKRepro                  _get_layer_from_native_surface(Ref<RenderingNativeSurface>) + 72
2  SGKRepro                  DisplayServerAppleEmbedded::window_get_size(...) const + 280
3  SGKRepro                  Window::_rect_changed_callback(...) + 296
4  SGKRepro                  CallableCustomMethodPointer<Window, void, Rect2i const&>::call(...) const + 180
5  SGKRepro                  Variant Callable::call<Variant>(...) const + 116
6  SGKRepro                  DisplayServerAppleEmbedded::_window_callback(...) const + 80
7  SGKRepro                  DisplayServerAppleEmbedded::resize_window(...) + 328
8  SGKRepro                  closure #1 in closure #1 in closure #1 in static DisplayServerAppleEmbeddedBridge.resizeWindow(_:size:id:) + 400
   ... 9 more frames of closures and withUnsafePointer inside DisplayServerAppleEmbeddedBridge.resizeWindow ...
18 SGKRepro                  static DisplayServerAppleEmbeddedBridge.resizeWindow(_:size:id:) + 280
19 SGKRepro                  UIGodotAppView.resizeWindow() + 1124
20 SGKRepro                  UIGodotAppView.startGodotInstance() + 1776
21 SGKRepro                  UIGodotAppView.didMoveToSuperview() + 628
22 SGKRepro                  @objc UIGodotAppView.didMoveToSuperview() + 44
23 UIKitCore                 __45-[UIView(Hierarchy) _postMovedFromSuperview:]_block_invoke + 900
24 UIKitCore                 -[UIView _postMovedFromSuperview:] + 508
25 UIKitCore                 -[UIView(Internal) _addSubview:positioned:relativeTo:] + 2324
   ... UIKitCore, then SwiftUI UIKitPlatformViewHost.init / PlatformViewChild.updateValue ...
```

## Environment

| | |
|---|---|
| SwiftGodotKit | `binary` branch at `b361ea0bc752dfe3dc596c8c6d906750631aba4f` (2026-10-20) |
| SwiftGodot | SwiftGodotBinary `0.99.2` (tag `v0.99.2`, `7d59d06`), the version SwiftGodotKit pins |
| libgodot payload | `v4.7.3-rc-swiftgodotkit.1` (`libgodot-ios.xcframework.zip`, sha256 `20610e7d5c52302481a51e9fc020fd68a6b113e9ad19e2c5e602ab5d1c330f37`). The engine reports `v4.7.3.rc.custom_build.324455d4e`. |
| Pack exported with | official Godot `4.7.2-stable` editor (`ed1daf0bf`) |
| Xcode / XcodeGen | 26.4.1 (17E202) / 2.44.1, Debug builds |
| Mac | macOS 26.5.1 (25F80), Apple M2 Pro |
| Simulator | iPhone 17 Pro, iOS 26.4.1 runtime (23E254a). SwiftGodotKit's simulator defaults are `--rendering-driver opengl3 --rendering-method gl_compatibility`. The engine logs "OpenGL ES 3.0 APPLE-23.1.1 - Compatibility - Using Device: Apple Inc. - Apple Software Renderer". |
| Device | iPad Pro 11-inch (3rd generation, M1, iPad13,5), iPadOS 26.6.2 (23G90). SwiftGodotKit's device defaults are `--rendering-driver metal --rendering-method mobile`. The engine logs "Metal 4.0 - Forward Mobile - Using Device #0: Apple - Apple M1 GPU (Apple7)". |

## Observations

1. **Removing the view frees its rendering resources, but the engine keeps running.** On the simulator, the app's `phys_footprint` is about 150 MB while the view is shown. It drops to about 69 MB within 0.3 s of removing the view.
2. **Nothing tells the engine that the surface is gone.**
   - `GodotAppView` doesn't implement `dismantleUIView`.
   - `UIGodotAppView` stops its `CADisplayLink` only in `removeFromSuperview()`.
   - Its `deinit` removes the rendering layer from its superlayer and releases it.
3. **On Metal, the engine still reaches the first view's layer.**
   - On the second mount, `startGodotInstance()` makes a new rendering layer and wraps it with `RenderingNativeSurfaceApple.create`.
   - It passes that surface to `DisplayServerAppleEmbedded.set_native_surface` (iOS-GodotAppView.swift:178–179), then calls `resizeWindow()`.
   - `window_get_size` still reaches a freed object through `_get_layer_from_native_surface`.
   - So the main window seems to keep the native surface it was created with, which points to the first view's layer, and `set_native_surface` doesn't seem to rebind a window that already exists.
   - The layer pointer is passed with `Unmanaged.passUnretained`. The fault in `objc_retain` suggests that nothing on the engine side keeps the layer alive either.
   - This is a reading of the code and the stacks, not a confirmed cause.
4. **On the simulator, the GLES3 rasterizer may be tied to the first view's GL context.** The second mount logs "Setting up an OpenGL ES 3.0 context." again, as the first did. The first frame drawn after it writes through a null pointer while copying canvas data. That fits a GL buffer mapping that returned null because the rasterizer's GL state belongs to the first view's layer and context. This is also unconfirmed.
5. **One startup error looks unrelated.** `mouse_get_position(): Mouse is not supported by this display server` is logged in every run, including runs that don't crash.

## Workaround

Keep one `GodotAppView` mounted for the app's lifetime, and hide it instead of removing it. In the app above, replace the `if`/`else` with:

```swift
GodotAppView().opacity(showsGame ? 1 : 0)
```

With that change, `-autoToggle 10` ran without a crash on both the simulator and the iPad. We use the same approach in a larger app, which calls `pause()` + `stopDrawing()` when it hides the view and `startDrawing()` + `resume()` when it shows it again. That has held up over repeated hide/show cycles on the simulator and on devices.
