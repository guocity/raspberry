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
