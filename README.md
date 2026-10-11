# Raspberry 3D Viewer (Universal iOS & macOS)

A fully offline raspberry viewer. iPhone and iPad use a native SwiftUI interface and Metal renderer. The macOS target retains the bundled WebGL viewer.

Original WebGL demonstration by **Luca Falasco (Luruke)**.

---

## ✨ Features

- **100% Offline**: iOS bundles the original raspberry mesh, style geometry, fuzz strands, and 13 textures converted to native ASTC assets. No HTML, JavaScript, WebKit, or runtime WASM decoding is used on iOS.
- **Universal Multiplatform App**: Builds and runs on macOS (Intel & Apple Silicon), iOS (iPhone), and iPadOS using SwiftUI.
- **Native Reel Control**: Rotates the berry and cycles through the six lighting presets.
- **Compact iPhone Controls**: A translucent SwiftUI capsule respects the device's safe areas, adapts to available width and larger text, and offers:
  - **Presets**: `Studio`, `Lantern`, `Ember`, `Dark`, `Backlit`, `Neon`
  - **Adjust Sheet**: Native sliders, color pickers, Fuzz and Auto-spin toggles, and camera reset.
  - **Touch Gestures**: Drag to rotate, pinch to zoom, and double-tap to reset.
- **Native Metal Pipeline**: SH9 baked light transfer, Beer-Lambert translucency, model-space and detail normals, studio light reflections, cavity glow, and camera-facing fuzz ribbons. Uses four-sample antialiasing and native depth-aware bokeh, and pauses rendering while the app is inactive. Depth of field defaults to the original focus offset (-0.75), focus range (1.6), and blur amount (3); adjust these in the native Adjust sheet. Studio lighting is evaluated natively; the macOS viewer's HDR environments, bloom, vignette, and grain are not used on iOS.
- **Original Reel Playback**: The native reel uses the original 16-shot, 16.2-second sequence with its camera orbits, close-ups, easing, roll, lighting sweeps, cut flashes, fades, and focus pulls. Shot looks come from the original preset data. Stopping playback restores the selected look and camera view.

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
│   │   ├── ContentView.swift         # Native iOS viewer / macOS WebKit wrapper
│   │   └── LocalSchemeHandler.swift  # macOS-only offline asset server
│   └── Metal/
│       ├── BerryShaders.metal        # Native Apple Metal shader code (MSL)
│       ├── BerryUniforms.swift       # SIMD structs & Observable state
│       ├── MetalBerryRenderer.swift  # MTKViewDelegate MetalKit pipeline
│       └── BerryControlsView.swift   # Native iPhone menu and adjustment sheet
├── Assets.xcassets/          # Multi-resolution Retina App Icon catalog
├── NativeAssets/            # iOS mesh, ASTC mip chains, and fuzz buffers
├── scripts/prepare-native-assets.cjs # Offline asset conversion using bundled decoders
├── Tests/NativeUITests/      # Real-device rendering and menu layout checks
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
Requires macOS 15.0 (Sequoia) or later.

Build and launch the app:
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
3. For a physical device, sign in under **Xcode → Settings → Apple Accounts**. In the **`Raspberry_iOS`** target's **Signing & Capabilities** tab, keep **Automatically manage signing** enabled and select your team. The project defaults to team `3AK89L7342`; choose your own team if needed.
4. Connect and unlock your iPhone/iPad, trust the Mac when prompted, and enable **Settings → Privacy & Security → Developer Mode** on the device.
5. Choose your destination (**iPhone Simulator**, **iPad Simulator**, or your connected iPhone/iPad), then press **Run (`⌘R`)**. Xcode creates or downloads the development certificate and provisioning profile for your device. If Xcode reports that the bundle identifier is unavailable, change `com.raspberry.ios` to a unique identifier in both Xcode and `project.yml`.

The iOS target uses automatic development signing. Only the macOS target disables signing for local builds. If you change your team or bundle identifier in Xcode, also update `project.yml` before regenerating the project.

Build products and per-user Xcode settings are ignored by Git. Bundled assets in `NativeAssets/` and `web/` remain versioned.

### 3. Regenerating Xcode Project (Optional)
If you add or rename files, you can regenerate the Xcode project using [XcodeGen](https://github.com/yonaskolb/XcodeGen):
```bash
xcodegen generate
```

If the original model or textures change, regenerate the native assets before building:
```bash
node scripts/prepare-native-assets.cjs
```

The iOS app supports portrait orientation only. Run the native device UI test with **Product → Test (`⌘U`)** using the `Raspberry_iOS` scheme and an unlocked connected iPhone. The test verifies rendering, preset selection, reel controls, the adjustment sheet, and portrait menu bounds, and saves screenshots in the test results.

---

## 🔬 Shading Architecture

1. **Precomputed Radiance Transfer (PRT) / Spherical Harmonics**:
   - Nine native ASTC textures preserve the original second-order SH coefficients pre-baked with subsurface scattering. Broad studio lights are projected into SH9 each frame.
2. **Analytical Turbid Bead Translucency**:
   - Each of the 117 drupelets is mathematically evaluated in the fragment shader as an individual spherical bead of juice:
     $$\text{extinction} = e^{-\sigma \cdot \text{chord}}$$
   - Evaluates internal refraction using Snell's law with $n = 1.33$.
3. **Inner Cavity Core Lamp**:
   - Simulates a lantern inside the hollow fruit core, glowing brightest where the fleshy wall is thin.
4. **GPU Strand Extrusion**:
   - The original 97,784 strands are converted offline. iOS renders half of them as camera-facing ribbons, with minimum pixel width and alpha fading to reduce shimmer.
