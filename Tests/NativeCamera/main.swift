import Foundation
import simd

struct Frame: Decodable { let position: [Float]; let radius, lightTurn: Float }
struct Scenario: Decodable { let aspect: Double; let frames: [Frame] }
let scenarios = try JSONDecoder().decode([Scenario].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
func close(_ a: Float, _ b: Float) { precondition(abs(a - b) < 0.00005, "Native \(a), original \(b)") }
for scenario in scenarios {
    let camera = BerryOrbitCamera(aspect: scenario.aspect)
    var frameIndex = 0
    func check() {
        camera.update(dt: 1 / 60)
        let original = scenario.frames[frameIndex]
        for axis in 0..<3 { close(camera.position[axis], original.position[axis]) }
        close(camera.distance, original.radius); close(camera.lightTurn, original.lightTurn)
        frameIndex += 1
    }
    for _ in 0..<240 { check() }
    camera.autoRotate = false
    camera.beginPinch()
    for scale in [1.25, 2.0, 4.0] {
        camera.zoom(scale: scale)
        for _ in 0..<60 { check() }
    }
    camera.endPinch(); camera.goHome()
    for _ in 0..<120 { check() }
    precondition(frameIndex == scenario.frames.count)
    // The new requested close-up limit goes past the original minimum radius.
    camera.beginPinch(); camera.zoom(scale: 100)
    for _ in 0..<180 { camera.update(dt: 1 / 60) }
    camera.endPinch()
    close(camera.distance, 1.6)
    let beforePosition = camera.position, beforeTarget = camera.target, beforeDistance = camera.distance
    camera.beginTranslation()
    camera.translate(delta: SIMD2(120, -60), height: 956)
    camera.endTranslation()
    let positionDelta = camera.position - beforePosition, targetDelta = camera.target - beforeTarget
    precondition(simd_length(targetDelta) > 0.01, "Two-finger drag must move the view")
    precondition(simd_length(positionDelta - targetDelta) < 0.00001, "Pan must translate camera and target together")
    close(camera.distance, beforeDistance)
    camera.goHome()
    for _ in 0..<180 { camera.update(dt: 1 / 60) }
    precondition(camera.target == .zero, "Reset must recenter the panned view")
    camera.beginPinch(); camera.zoom(scale: 0.0001)
    for _ in 0..<240 { camera.update(dt: 1 / 60) }
    camera.endPinch()
    close(camera.distance, Float(26 * camera.fit))
    print("PASS portrait \(scenario.aspect): original intro/zoom/reset, closer macro limit, two-finger pan, zoom-out limit")
}
