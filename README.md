# Raspberry 3D Viewer (Universal iOS & macOS)

A 100% offline, standalone native Apple multiplatform app (iOS, iPadOS, macOS) for photorealistic 3D raspberry rendering with real-time Beer-Lambert translucency, Spherical Harmonics transfer (PRT), hollow core lighting, and cinematic reel playback.

Original WebGL demonstration by **Luca Falasco (Luruke)**.

---

## ✨ Features

- **100% Offline**: All 52MB of assets (3D GLB model, fuzz binary buffer, 13 KTX2 textures, 8 HDR environment maps, and Draco/Basis WASM transcoders) are bundled locally. **Zero network calls to external websites.**
- **Universal Multiplatform App**: Builds and runs on macOS (Intel & Apple Silicon), iOS (iPhone), and iPadOS using SwiftUI.
- **Cinematic Reel Control**: Play/Stop Reel button that transitions through choreographed camera angles, lighting states, and presets.
- **Compact & Modern UI Dock**: Minimalist, emoji-free frosted glass controls:
  - **Presets**: `Studio`, `Lantern`, `Ember`, `Dark`, `Backlit`, `Neon`
  - **Adjust Drawer**: Sliders for Key Light, Cavity Lantern Glow, Bead Translucency, Background color picker, Fuzz toggle, and Auto-spin
  - **Code Modal**: Built-in Apple Metal Shading Language (`BerryShaders.metal`) and Swift viewer code with one-click copy
- **Native Metal Pipeline Included**: Complete MSL vertex/fragment shaders and MetalKit pipeline implementing Beer-Lambert bead extinction ($e^{-\sigma \cdot \text{chord}}$) and SH9 transfer decoding.

---

## 📁 Repository Structure

```
raspberry/
├── Raspberry.xcodeproj       # Universal Xcode project for iOS, iPadOS, and macOS
├── project.yml               # XcodeGen project specification
├── run_mac.sh                # Build & launch macOS app immediately
├── open_xcode.sh             # Open project in Xcode
├── Shared/
│   ├── App/
│   │   ├── RaspberryApp.swift        # Universal SwiftUI App entrypoint
│   │   ├── ContentView.swift         # Cross-platform WebKit view wrapper
│   │   └── LocalSchemeHandler.swift  # Offline asset server for WKWebView
│   └── Metal/
│       ├── BerryShaders.metal        # Native Apple Metal shader code (MSL)
│       ├── BerryUniforms.swift       # SIMD structs & Observable state
│       ├── MetalBerryRenderer.swift  # MTKViewDelegate MetalKit pipeline
│       └── BerryControlsView.swift   # Native SwiftUI controls drawer
├── Assets.xcassets/          # Multi-resolution Retina App Icon catalog
├── build/
│   └── macOS/Raspberry.app   # Compiled, runnable macOS Application
└── web/                      # 100% Offline Asset Directory (52 MB)
    ├── index.html            # Standalone entrypoint (analytics removed)
    ├── overlay.js            # Injected compact controls & Reel controller
    ├── assets/               # Models, KTX2 textures, SH PRT textures, HDRIs
    └── libs/                 # Basis Universal & Draco WASM decoders
```

---

## 🚀 How to Run

### 1. macOS (Instant Launch)
Double-click the pre-built app or run:
```bash
./run_mac.sh
```
Or open the app located at:
`build/macOS/Raspberry.app`

### 2. iOS / iPadOS (Simulator or Physical Device)
1. Open the project in Xcode:
   ```bash
   ./open_xcode.sh
   ```
2. Select the **`Raspberry_iOS`** scheme at the top of Xcode.
3. Choose your destination (**iPhone Simulator**, **iPad Simulator**, or your plugged-in iPhone/iPad).
4. Press **Run (`⌘R`)**.

### 3. Regenerating Xcode Project (Optional)
If you add or rename files, you can regenerate the Xcode project using [XcodeGen](https://github.com/yonaskolb/XcodeGen):
```bash
xcodegen generate
```

---

## 🔬 Shading Architecture

1. **Precomputed Radiance Transfer (PRT) / Spherical Harmonics**:
   - 9 KTX2 textures (`transfer_sh0.ktx2` .. `transfer_sh8.ktx2`) store 2nd-order SH coefficients pre-baked from offline path-tracing with subsurface scattering.
2. **Analytical Turbid Bead Translucency**:
   - Each of the 117 drupelets is mathematically evaluated in the fragment shader as an individual spherical bead of juice:
     $$\text{extinction} = e^{-\sigma \cdot \text{chord}}$$
   - Evaluates internal refraction using Snell's law with $n = 1.33$.
3. **Inner Cavity Core Lamp**:
   - Simulates a lantern inside the hollow fruit core, glowing brightest where the fleshy wall is thin.
4. **GPU Strand Extrusion**:
   - 97,784 fuzz hairs (`raspberry_fuzz.bin`) dynamically extruded into camera-facing ribbons with Marschner fiber lighting and subpixel anti-aliasing clamping.
