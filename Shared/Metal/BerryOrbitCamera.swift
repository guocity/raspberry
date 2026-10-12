import Foundation
import simd

/// Native camera controls using the original viewer's orbit/zoom equations.
final class BerryOrbitCamera {
    private struct Pose { var theta, phi, radius: Double }
    private struct Intro { var time = 0.0 }
    // Extended past the original 2.6 limit for the requested extreme close-ups.
    private let minimumRadius = 1.6, maximumRadius = 26.0
    private let minimumElevation = -80.0 * .pi / 180, maximumElevation = 86.0 * .pi / 180
    private var current: Pose
    private var goal: Pose
    private var home: Pose
    private var velocity = SIMD2<Double>.zero
    private var intro: Intro?
    private var introTurn = 0.0
    private var spin = 0.0, spinRamp = 0.0
    private var panning = false, pinching = false, translating = false
    private var targetPosition = SIMD3<Double>.zero
    private var pinchRadius = 0.0
    private(set) var fit: Double
    var autoRotate = true
    var autoRotateSpeed = 1.0
    var distance: Float { Float(current.radius) }
    var lightTurn: Float { Float(spin + introTurn) }
    var angleDegrees: Double { (current.theta + spin) * 180 / .pi }
    var target: SIMD3<Float> { SIMD3(Float(targetPosition.x), Float(targetPosition.y), Float(targetPosition.z)) }
    var position: SIMD3<Float> {
        let theta = current.theta + spin, phi = current.phi, radius = current.radius
        return target + SIMD3(Float(radius * cos(phi) * sin(theta)), Float(radius * sin(phi)), Float(radius * cos(phi) * cos(theta)))
    }

    init(aspect: Double, reducedMotion: Bool = false) {
        fit = max(1, 0.86 / aspect)
        let radius = sqrt(1.57 * 1.57 + 3.4 * 3.4 + 8.98 * 8.98)
        let pose = Pose(theta: atan2(1.57, 8.98), phi: asin(3.4 / radius), radius: radius * fit)
        current = pose; goal = pose; home = pose
        if !reducedMotion { intro = Intro(); spinRamp = 1; update(dt: 0) }
    }
    func setAspect(_ aspect: Double) {
        let newFit = max(1, 0.86 / aspect)
        guard abs(newFit - fit) >= 0.001 else { return }
        let ratio = newFit / fit
        fit = newFit; goal.radius *= ratio; home.radius *= ratio
    }
    func cancelIntro() {
        if intro != nil { intro = nil; goal = current }
    }
    func beginPan() { cancelIntro(); panning = true; velocity = .zero }
    func drag(delta: SIMD2<Double>, speed: SIMD2<Double>, height: Double) {
        let sensitivity = min(1, max(0.35, goal.radius / (8.6 * fit)))
        let factor = Double.pi / max(1, height) * sensitivity
        goal.theta -= delta.x * factor
        goal.phi += delta.y * factor
        let desired = SIMD2(-speed.x * factor, speed.y * factor)
        velocity += (desired - velocity) * 0.4
    }
    func endPan(cancelled: Bool = false) {
        panning = false
        if cancelled || pinching { velocity = .zero }
        let magnitude = simd_length(velocity)
        if magnitude > 7 { velocity *= 7 / magnitude }
    }
    func beginPinch() {
        cancelIntro(); pinching = true; velocity = .zero; pinchRadius = goal.radius
    }
    func zoom(scale: Double) {
        // UIPinchGestureRecognizer.scale is cumulative from the gesture's start.
        // Like the original two-pointer distance ratio, use the starting radius.
        goal.radius = pinchRadius / max(scale, 0.0001)
    }
    func endPinch() { pinching = false; velocity = .zero }
    func beginTranslation() { cancelIntro(); translating = true; velocity = .zero }
    func translate(delta: SIMD2<Double>, height: Double) {
        let theta = current.theta + spin, phi = current.phi
        let right = SIMD3(cos(theta), 0, -sin(theta))
        let up = SIMD3(-sin(phi) * sin(theta), cos(phi), -sin(phi) * cos(theta))
        let unitsPerPoint = 2 * current.radius * tan(20 * Double.pi / 180 / 2) / max(1, height)
        targetPosition += (-right * delta.x + up * delta.y) * unitsPerPoint
    }
    func endTranslation() { translating = false; velocity = .zero }
    func goHome() {
        cancelIntro()
        targetPosition = .zero
        let turns = floor((goal.theta - home.theta) / (2 * .pi) + 0.5)
        goal = Pose(theta: home.theta + turns * 2 * .pi, phi: home.phi, radius: home.radius)
        velocity = .zero
    }
    func update(dt: Double) {
        let dt = min(dt, 0.1)
        func approach(_ a: Double, _ b: Double, _ time: Double) -> Double { a + (b - a) * (1 - exp(-dt / time)) }
        spinRamp = approach(spinRamp, autoRotate && !panning && !pinching && !translating ? 1 : 0, 0.5)
        spin = (spin + autoRotateSpeed * 6 * .pi / 180 * dt * spinRamp).truncatingRemainder(dividingBy: 2 * .pi)
        if var animation = intro {
            animation.time += dt
            let t = min(1, max(0, animation.time / 3.4))
            let ease = pow(1 - t * t * (3 - 2 * t), 2)
            let turn = -160.0 * .pi / 180 * (autoRotate && autoRotateSpeed < 0 ? -1 : 1)
            current.theta = home.theta + turn * ease
            current.phi = min(maximumElevation, max(minimumElevation, home.phi + 10 * .pi / 180 * ease))
            current.radius = home.radius * (1 + 0.75 * ease)
            goal = current; velocity = .zero; introTurn = current.theta - home.theta
            intro = t >= 1 ? nil : animation
        } else {
            introTurn = abs(introTurn) < 0.0001 ? 0 : approach(introTurn, 0, 0.35)
            if !panning && !pinching && !translating {
                goal.theta += velocity.x * dt; goal.phi += velocity.y * dt
                velocity *= exp(-dt * 3.5)
            }
            if goal.phi < minimumElevation || goal.phi > maximumElevation {
                goal.phi = min(maximumElevation, max(minimumElevation, goal.phi)); velocity.y = 0
            }
            goal.radius = min(maximumRadius * fit, max(minimumRadius, goal.radius))
            current.theta = approach(current.theta, goal.theta, 0.075)
            current.phi = approach(current.phi, goal.phi, 0.075)
            current.radius = exp(approach(log(current.radius), log(goal.radius), 0.13))
        }
    }
}

/// Low-latency portrait motion mapping, shared with the native motion checks.
enum BerryMotionRotation {
    static func upright(direction: SIMD3<Float>) -> (direction: SIMD3<Float>, up: SIMD3<Float>) {
        let yaw = atan2(direction.x, direction.z)
        // Stay clear of the poles where a world-up camera can become singular.
        let limit: Float = 80 * .pi / 180
        let pitch = min(limit, max(-limit, atan2(direction.y, hypot(direction.x, direction.z))))
        let z = SIMD3<Float>(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
        let right = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), z))
        return (z, simd_cross(z, right))
    }

    static func relative(reference: simd_quatf, attitude: simd_quatf,
                         rotationRate: SIMD3<Float>, sampleAge: Double) -> simd_quatf {
        // Predict only a short sensor-to-render delay, never a stale/background sample.
        let horizon = Float(min(max(sampleAge, 0), 1.0 / 50))
        let speed = simd_length(rotationRate)
        let prediction = speed > 0.0001
            ? simd_quatf(angle: speed * horizon, axis: rotationRate / speed)
            : simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        return simd_normalize(reference.inverse * attitude * prediction)
    }
}
