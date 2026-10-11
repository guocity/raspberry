import Foundation
import simd
import SwiftUI

public struct LightUniform {
    public var direction: SIMD3<Float> = SIMD3<Float>(0, 1, 0)
    public var _pad1: Float = 0
    public var color: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    public var _pad2: Float = 0
}

public struct BerryUniforms {
    public var modelViewProjection = matrix_identity_float4x4
    public var modelRotation = matrix_identity_float3x3
    public var cameraPosition = SIMD3<Float>(0, 0, 5)
    public var _pad0: Float = 0
    public var lights: (LightUniform, LightUniform, LightUniform) = (LightUniform(), LightUniform(), LightUniform())
    
    public var tint = SIMD3<Float>(1, 1, 1)
    public var sss: Float = 1.0
    public var beadGlow: Float = 1.2
    public var seeThrough: Float = 1.0
    public var transColor = SIMD3<Float>(0.85, 0.05, 0.08)
    public var transDepth: Float = 0.22
    public var roughnessScale: Float = 1.0
    public var roughnessBias: Float = 0.0
    public var specular: Float = 1.0
    public var aoPower: Float = 1.0
    public var tScale: (Float, Float, Float, Float, Float, Float, Float, Float, Float) = (0.175, 0.161, 0.156, 0.157, 0.056, 0.055, 0.067, 0.056, 0.060)
    
    public var innerPos = SIMD3<Float>(0, 1.15, 0)
    public var _pad1: Float = 0
    public var innerColor = SIMD3<Float>(0, 0, 0)
    public var innerWall: Float = 0.55
    public var berryCenter = SIMD3<Float>(0, 1.15, 0)
    public var _pad2: Float = 0
    
    public init() {}
}

public class BerrySettings: ObservableObject {
    @Published public var keyIntensity: Float = 3.5
    @Published public var keyColor: Color = .white
    @Published public var keyAzimuth: Float = 45.0
    @Published public var keyElevation: Float = 30.0

    @Published public var innerIntensity: Float = 0.0
    @Published public var innerColor: Color = Color(red: 1.0, green: 0.35, blue: 0.1)
    @Published public var innerHeight: Float = 1.15
    @Published public var innerWall: Float = 0.55

    @Published public var ambientIntensity: Float = 0.3
    @Published public var backgroundColor: Color = Color(red: 0.07, green: 0.07, blue: 0.07)

    @Published public var sss: Float = 1.0
    @Published public var beadGlow: Float = 1.2
    @Published public var transColor: Color = Color(red: 0.85, green: 0.05, blue: 0.08)
    @Published public var transDepth: Float = 0.22
    @Published public var roughness: Float = 0.28
    @Published public var specular: Float = 1.0

    @Published public var fuzzVisible: Bool = true
    @Published public var fuzzWidth: Float = 1.0
    @Published public var backlightHalo: Float = 2.5
    
    public init() {}
}
