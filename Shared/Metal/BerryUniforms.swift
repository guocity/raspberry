import SwiftUI
import simd

// Every GPU field is a matrix or float4, keeping Swift and Metal alignment identical.
struct BerryUniforms {
    var mvp = matrix_identity_float4x4
    var model = matrix_identity_float4x4
    var camera = SIMD4<Float>(0, 0, 8, 1)
    var lightDirections = (SIMD4<Float>.zero, SIMD4<Float>.zero, SIMD4<Float>.zero)
    var lightColors = (SIMD4<Float>.zero, SIMD4<Float>.zero, SIMD4<Float>.zero)
    var sh = (SIMD4<Float>.zero, SIMD4<Float>.zero, SIMD4<Float>.zero,
              SIMD4<Float>.zero, SIMD4<Float>.zero, SIMD4<Float>.zero,
              SIMD4<Float>.zero, SIMD4<Float>.zero, SIMD4<Float>.zero)
    var skin = SIMD4<Float>(1, 1.2, 0.22, 1)
    var innerPosition = SIMD4<Float>(0, 1.15, 0, 0.55)
    var innerColor = SIMD4<Float>.zero
    var transmission = SIMD4<Float>(0.85, 0.05, 0.08, 1)
    var viewport = SIMD4<Float>(1, 1, 1, 2.5)
    var ambient = SIMD4<Float>(0.3, 0.3, 0.3, 1)
    var material = SIMD4<Float>(0, 0.5, 1, 1)
    var sheen = SIMD4<Float>(1, 0.85, 0.85, 0.66)
    var effects = SIMD4<Float>(1, 1, 1, 1)
    var fuzz = SIMD4<Float>(0.92, 0.86, 0.84, 0.65)
    var surface = SIMD4<Float>(1, 1, 1.1, 0)
}

enum BerryPreset: String, CaseIterable, Identifiable {
    case studio = "Studio", lantern = "Lantern", ember = "Ember"
    case dark = "Dark", backlit = "Backlit", neon = "Neon"
    var id: String { rawValue }
}

final class BerrySettings: ObservableObject {
    @Published var preset: BerryPreset = .studio
    @Published var keyIntensity: Float = 3.5
    @Published var keyColor: Color = .white
    @Published var keyAzimuth: Float = 45
    @Published var innerIntensity: Float = 0
    @Published var innerColor = Color(red: 1, green: 0.35, blue: 0.1)
    @Published var innerWall: Float = 0.55
    @Published var ambientIntensity: Float = 0.12
    @Published var backgroundColor: Color = .black
    @Published var sss: Float = 1
    @Published var beadGlow: Float = 1.2
    @Published var transColor = Color(red: 0.85, green: 0.05, blue: 0.08)
    @Published var transDepth: Float = 0.22
    @Published var roughness: Float = 1
    @Published var fuzzVisible = true
    @Published var backlightHalo: Float = 2.5
    @Published var depthOfField = true
    @Published var focusOffset: Float = -0.75
    @Published var focusRange: Float = 1.6
    @Published var blurAmount: Float = 3
    @Published var spinning = true
    @Published var gyroscopeEnabled = false
    @Published var fastRendering = true
    @Published var reelPlaying = false
    @Published var reelShotName: String?
    @Published var resetCamera = UUID()
    @Published var renderError: String?
    private(set) var referenceLook: BerryReelData.Look?
    private let originalLooks = (try? BerryReelData.load().looks) ?? [:]

    func select(_ preset: BerryPreset) {
        self.preset = preset
        referenceLook = nil
        keyColor = .white
        keyAzimuth = 45
        keyIntensity = 3.5
        ambientIntensity = 0.12
        innerIntensity = 0
        beadGlow = 1.2
        backgroundColor = .black
        sss = 1; roughness = 1; innerWall = 0.55
        innerColor = Color(red: 1, green: 0.35, blue: 0.1)
        transColor = Color(red: 0.85, green: 0.05, blue: 0.08)
        transDepth = 0.22; backlightHalo = 2.5
        switch preset {
        case .studio: break
        case .lantern:
            keyIntensity = 0.8; ambientIntensity = 0.025; innerIntensity = 4
        case .ember:
            keyIntensity = 1.8; keyColor = Color(red: 1, green: 0.48, blue: 0.22)
            innerIntensity = 2; ambientIntensity = 0.04
        case .dark:
            keyIntensity = 0.55; ambientIntensity = 0.015
        case .backlit:
            referenceLook = originalLooks["Backlit"]
            keyAzimuth = 168; keyIntensity = 7; ambientIntensity = 0.18; beadGlow = 1
            backgroundColor = Color(red: 246.0 / 255, green: 246.0 / 255, blue: 246.0 / 255)
            sss = 1; roughness = 1; innerWall = 0.6
            transColor = Color(red: 208.0 / 255, green: 64.0 / 255, blue: 31.0 / 255)
            transDepth = 0.15; backlightHalo = 3
        case .neon:
            keyColor = Color(red: 0.35, green: 0.55, blue: 1)
            keyAzimuth = -65; keyIntensity = 4; innerIntensity = 1.5
        }
    }
}
