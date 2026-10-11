# Raspberry 3D Viewer for iOS & macOS (Metal + Swift)

This package contains the native Apple Metal and SwiftUI implementation of the photorealistic 3D raspberry renderer.

## Architecture

1. **`BerryShaders.metal`**:
   - Evaluates 2nd-order Spherical Harmonics transfer functions (PRT).
   - Computes analytical turbid bead translucency with Beer-Lambert absorption law ($e^{-\sigma \cdot \text{chord}}$).
   - Simulates Snell's law refraction ($n = 1.33$) through individual drupelet beads.
   - Computes inner cavity lamp illumination with wall thickness attenuation.

2. **`BerryUniforms.swift`**:
   - Memory layout and SIMD struct definitions matching MSL buffers.
   - Observable `BerrySettings` binding sliders and color pickers.

3. **`MetalBerryRenderer.swift`**:
   - `MTKViewDelegate` rendering pipeline using Apple MetalKit.

4. **`BerryControlsView.swift`**:
   - Native SwiftUI controls for Key light, Cavity lantern, Translucency, and Fuzz.

## Running on iOS Devices

1. Create a new iOS App project in Xcode.
2. Select SwiftUI and Metal.
3. Drag these Swift and Metal files into your Xcode project.
4. Add `raspberry.glb` (or converted ModelIO mesh) and textures to Assets.xcassets.
5. Build and run on your iPhone or iPad!
