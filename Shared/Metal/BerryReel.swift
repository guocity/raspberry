import Foundation
import simd

struct BerryReelData: Decodable {
    let shots: [Shot]
    let looks: [String: Look]
    let options: Options
    let fov: Double

    enum Track: Decodable {
        case constant(Double), range(Double, Double)
        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let number = try? value.decode(Double.self) { self = .constant(number) }
            else {
                let pair = try value.decode([Double].self)
                guard pair.count == 2 else { throw DecodingError.dataCorruptedError(in: value, debugDescription: "A reel track needs two endpoints") }
                self = .range(pair[0], pair[1])
            }
        }
        func value(_ t: Double) -> Double {
            switch self { case .constant(let value): return value; case .range(let a, let b): return a + (b - a) * t }
        }
        var first: Double { value(0) }
        var isRange: Bool { if case .range = self { return true }; return false }
    }
    struct Shot: Decodable {
        let preset: String
        let beats: Double
        let distance, elevation: Track
        let sweep, fade, lookY, roll, yaw, lookSide, focusPull, fov: Track?
        let bokeh, spin: Double?
        let ease, lights: String?
    }
    struct Options: Decodable {
        let beat, spin, pushIn, flash, drift: Double
        let loop: Bool
    }
    struct Light: Decodable { let azimuth, elevation, intensity, size, stretch: Float; let color: String }
    struct Inner: Decodable { let intensity, height, wall: Float; let color: String }
    struct Lights: Decodable { let key, fill, rim: Light; let inner: Inner; let softboxSquare: Float }
    struct Environment: Decodable {
        let ambientColor, background: String
        let ambientIntensity, ambientGradient, backgroundIntensity, reflectionIntensity: Float
    }
    struct Skin: Decodable {
        let sss, beadGlow, transDepth, roughnessScale, roughnessBias, detailStrength, detailScale: Float
        let specular, ior, seeThrough, seed, sheen, aoPower: Float
        let transColor, sheenColor: String
    }
    struct Fuzz: Decodable { let width, minPixels, opacity, backlight: Float; let color: String }
    struct Styles: Decodable { let brightness, specular: Float }
    struct Post: Decodable { let exposure, focusOffset, focusRange, bokehScale: Float; let dof: Bool }
    struct Look: Decodable { let lights: Lights; let environment: Environment; let skin: Skin; let fuzz: Fuzz; let styles: Styles; let post: Post }

    static func load() throws -> Self {
        guard let url = Bundle.main.url(forResource: "reel", withExtension: "json", subdirectory: "NativeAssets") else {
            throw NSError(domain: "BerryReel", code: 1, userInfo: [NSLocalizedDescriptionKey: "The original reel sequence is missing."])
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

/// Port of the original Tp playback function. Calculations remain Double until
/// the result reaches Metal, so shot cuts and easing agree with JavaScript.
final class BerryReel {
    struct Frame {
        let index: Int
        let preset: String
        let position, target: SIMD3<Float>
        let roll, fov, lightTurn, gain, focus, blur: Float
        let look: BerryReelData.Look
    }
    let data: BerryReelData
    var duration: Double { data.shots.reduce(0) { $0 + $1.beats } * data.options.beat }
    private(set) var active = false
    private(set) var time: Double = 0
    private var angle: Double = 0
    private var index = -1
    private var sinceCut: Double = 0

    init(data: BerryReelData) { self.data = data }
    func start(angle: Double) {
        active = true; time = 0; self.angle = angle; index = -1; sinceCut = 0
    }
    func stop() { active = false }

    func update(dt: Double, aspect: Double) -> Frame? {
        guard active else { return nil }
        let options = data.options
        time += dt
        if time >= duration {
            guard options.loop else { stop(); return nil }
            time.formTruncatingRemainder(dividingBy: duration)
        }
        var shotIndex = 0, shotStart = 0.0
        while shotIndex < data.shots.count - 1 && time >= shotStart + data.shots[shotIndex].beats * options.beat {
            shotStart += data.shots[shotIndex].beats * options.beat
            shotIndex += 1
        }
        let shot = data.shots[shotIndex]
        if shotIndex != index { index = shotIndex; sinceCut = 0 }
        sinceCut += dt
        let h = (time - shotStart) / (shot.beats * options.beat)
        let g: Double
        switch shot.ease {
        case "in": g = h * h
        case "out": g = 1 - pow(1 - h, 3)
        case "inOut": g = h * h * (3 - 2 * h)
        case "outExpo": g = h >= 1 ? 1 : 1 - pow(2, -10 * h)
        case "outBack": g = 1 + 2.70158 * pow(h - 1, 3) + 1.70158 * pow(h - 1, 2)
        default: g = h
        }
        func value(_ track: BerryReelData.Track?, fallback: Double = 0) -> Double { track?.value(g) ?? fallback }
        let radians = Double.pi / 180
        angle += options.spin * (shot.spin ?? 1) * dt
        let yaw = (angle + value(shot.yaw)) * radians
        let elevation = shot.elevation.value(g) * radians
        let initialFOV = shot.fov?.first ?? data.fov
        let fov = value(shot.fov, fallback: data.fov)
        let fovFit = tan(initialFOV * radians / 2) / tan(fov * radians / 2)
        let portraitFit = max(1, 0.86 / aspect)
        let push = shot.distance.isRange ? 1 : 1 - options.pushIn * h
        let distance = shot.distance.value(g) * portraitFit * fovFit * push
        let drift = options.drift * 0.012
        let side = value(shot.lookSide) + drift * sin(time * 4.3 + 1)
        let height = value(shot.lookY) + drift * sin(time * 5.9)
        let x = side * cos(yaw), z = -side * sin(yaw)
        guard let look = data.looks[shot.preset] else { return nil }
        return Frame(index: index, preset: shot.preset,
            position: SIMD3(Float(x + distance * cos(elevation) * sin(yaw)), Float(height + distance * sin(elevation)), Float(z + distance * cos(elevation) * cos(yaw))),
            target: SIMD3(Float(x), Float(height), Float(z)), roll: Float(value(shot.roll) * radians), fov: Float(fov),
            lightTurn: Float((shot.lights == "world" ? 0 : yaw) + value(shot.sweep) * radians),
            gain: Float((1 + options.flash * exp(-sinceCut / 0.07)) * value(shot.fade, fallback: 1)),
            focus: Float(distance + value(shot.focusPull)), blur: Float(shot.bokeh ?? Double(look.post.bokehScale)), look: look)
    }
}
