# Native iPhone and iPad viewer

The `Raspberry_iOS` target compiles these Swift and Metal files and bundles `NativeAssets/`. It does not compile the macOS WebKit scheme handler or bundle `web/`.

- `BerryControlsView.swift`: SwiftUI viewer, translucent preset/reel/adjust capsule, and native adjustment sheet.
- `BerryUniforms.swift`: Observable controls and an explicitly aligned GPU uniform buffer.
- `BerryReel.swift`: Native port of the original reel timeline and camera equations, using `NativeAssets/reel.json`. Includes all 16 shots, original timing/easing, portrait framing, roll, push-in/drift, cut flash/fade, lighting sweeps, and focus pulls. Playback uses temporary shot settings, leaving the user's camera and adjustments intact when stopped.
- `MetalBerryRenderer.swift`: MetalKit rendering, original mesh and ASTC mip loading, studio lights projected into SH9, touch rotation/zoom, and reel playback.
- `MetalDepthOfField.swift` / `DepthOfField.metal`: Resolved MSAA scene depth, half-resolution circle-of-confusion prefilter, 24-tap golden-angle bokeh, gap fill, and full-resolution composite. Focus follows the camera while zooming, with the original offset/range/blur defaults and native adjustment controls. Disabling DOF or setting blur to zero skips the blur passes. Render targets are reused until the drawable size changes; iOS MSAA attachments use tile memory.
- `BerryShaders.metal`: Baked SH9 light transfer, normal and pore detail, Beer-Lambert flesh transmission, seed/cavity lighting, studio reflections, styles, and fuzz ribbons.

The original assets are converted offline with `node scripts/prepare-native-assets.cjs`. Bundled Draco/Basis decoders are used only by that build-time script. Native mesh files have a validated header, packed vertex attributes and UInt32 triangle indices. Native textures contain validated ASTC 4×4 mip chains. Fuzz uses the original four-point strands.

Regenerate reel data with `node scripts/prepare-native-reel.cjs`. This extracts the original shot/preset literals for native decoding; iOS does not execute JavaScript. The native reel's lighting uses the original key/fill/rim positions, sizes, strip stretch, colors, and intensities.

Open `Raspberry.xcodeproj`, select `Raspberry_iOS` and an iPhone, then run. The app supports portrait orientation only. The device UI test (`⌘U`) checks actual berry rendering, native controls, and portrait bounds, with screenshots attached to the test result.

The offscreen GPU regression verifies that the focal plane stays sharp, distant details blur, a focus pull swaps the sharp plane, zero blur matches disabled DOF, and the composite preserves image orientation at both even and odd portrait resolutions:

```sh
xcrun -sdk macosx metal -fmodules-cache-path=/tmp/raspberry-metal-module-cache -c Shared/Metal/DepthOfField.metal -o /tmp/raspberry-dof.air
xcrun -sdk macosx metallib /tmp/raspberry-dof.air -o /tmp/raspberry-dof.metallib
xcrun swiftc -module-cache-path /tmp/raspberry-swift-module-cache Shared/Metal/MetalDepthOfField.swift Tests/MetalDepthOfField/main.swift -o /tmp/raspberry-dof-check
MTL_DEBUG_LAYER=1 /tmp/raspberry-dof-check /tmp/raspberry-dof.metallib
```

Compare native playback against the original JavaScript function, including two loops at three timestep sizes and two portrait aspect ratios:

```sh
node scripts/prepare-native-reel.cjs /tmp/raspberry-reel-reference.json
xcrun swiftc -module-cache-path /tmp/raspberry-swift-module-cache Shared/Metal/BerryReel.swift Tests/NativeReel/main.swift -o /tmp/raspberry-reel-check
/tmp/raspberry-reel-check NativeAssets/reel.json /tmp/raspberry-reel-reference.json
```

Motion rotation checks (recenter, pitch/yaw/roll, immediate response, and bounded sensor-delay prediction):

```sh
xcrun swiftc -module-cache-path /tmp/raspberry-swift-module-cache Shared/Metal/BerryOrbitCamera.swift Tests/NativeMotion/main.swift -o /tmp/raspberry-motion-check
/tmp/raspberry-motion-check
```

Gyroscope control samples Core Motion at a requested 120 Hz and uses its fused attitude directly, with up to 20 ms of rotation-rate prediction. It suspends auto spin and cancels the intro orbit so those animations do not compete with device movement. Actual sensor cadence and rendering frame rate depend on the device; evaluate motion latency on a physical iPhone.

Fast rendering defaults on; gyroscope defaults off. Both switches are in the View menu at the top of Adjust. Fast rendering reduces scene pixels by at least half, halves the already reduced fuzz instance count, and bypasses the three blur passes. The composite scales the scene to the drawable. A two-frame GPU submission limit skips busy frames instead of queueing old poses.

Render-size checks:

```sh
xcrun swiftc -module-cache-path /tmp/raspberry-swift-module-cache Shared/Metal/MetalDepthOfField.swift Tests/NativeRenderQuality/main.swift -o /tmp/raspberry-quality-check
/tmp/raspberry-quality-check
```

The GPU regression also checks reduced-resolution upscaling, drawable coverage, orientation, and restoring full detail.

Gyroscope orbit keeps the berry upright with a world-up camera, ignores phone roll, and limits elevation to ±80° to avoid pole flips. The motion checks cover roll removal and pole stability.

The motion manager is created only when Gyroscope is enabled, and released when disabled, inactive, or playing the reel. Apple framework console diagnostics require an on-device backtrace for attribution; the app does not read managed preference files or call synchronous Swift concurrency bridges.

On-device console investigation (2026-10-12, iOS 27.0.1 / 24A446): both `unsafeForcedSync called from Swift Concurrent context` and the missing `SFBarButtonGroupContainerAccessibility` warning were reproduced. Xcode's Library and Subsystem metadata identify **AXCoreUtilities** and **com.apple.Accessibility** for both messages. The exact concurrency warning string is also present in that framework's device-support binary. The recommended `libswiftos.dylib` / `os_log` breakpoint resolved but did not capture either warning on this OS build; no warning backtrace was obtained. This identifies the emitting framework, but does not prove the full call path or that the diagnostic is harmless. No app-level fix was established, and the temporary breakpoint was removed. Apple's guidance: https://developer.apple.com/forums/thread/802423.
