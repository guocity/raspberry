// Run with BerryReel.swift, NativeAssets/reel.json, and the reference fixtures
// produced by scripts/prepare-native-reel.cjs from the original JavaScript.
import Foundation
import simd

struct ReferenceFrame: Decodable {
    let position, target: [Float]
    let roll, fov, turn, gain, focus, blur: Float
    let preset: String
    let time: Double
}
struct Scenario: Decodable { let aspect, dt: Double; let frames: [ReferenceFrame] }
let decoder = JSONDecoder()
let data = try decoder.decode(BerryReelData.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let scenarios = try decoder.decode([Scenario].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
func close(_ a: Float, _ b: Float, _ context: String) {
    precondition(abs(a - b) < 0.00002, "\(context): native \(a), original \(b)")
}
var total = 0
for scenario in scenarios {
    let reel = BerryReel(data: data)
    precondition(abs(reel.duration - 16.2) < 1e-9)
    precondition(reel.update(dt: scenario.dt, aspect: scenario.aspect) == nil, "Stopped reel must not advance")
    reel.start(angle: 17)
    var cuts = Set<Int>()
    for (i, original) in scenario.frames.enumerated() {
        let frame = reel.update(dt: scenario.dt, aspect: scenario.aspect)!
        precondition(frame.preset == original.preset, "Shot order differs at frame \(i): \(frame.preset) / \(original.preset)")
        precondition(abs(reel.time - original.time) < 1e-9, "Timeline differs at frame \(i)")
        for axis in 0..<3 {
            close(frame.position[axis], original.position[axis], "Camera \(i)/\(axis)")
            close(frame.target[axis], original.target[axis], "Target \(i)/\(axis)")
        }
        for (native, expected, name) in [(frame.roll,original.roll,"roll"), (frame.fov,original.fov,"fov"),
            (frame.lightTurn,original.turn,"light sweep"), (frame.gain,original.gain,"flash/fade"),
            (frame.focus,original.focus,"focus pull"), (frame.blur,original.blur,"bokeh")] {
            close(native, expected, "\(name) at frame \(i)")
        }
        cuts.insert(frame.index)
        total += 1
    }
    precondition(cuts.count == 16, "Every original shot must play")
    reel.stop()
    let stoppedTime = reel.time
    precondition(reel.update(dt: 1, aspect: scenario.aspect) == nil && reel.time == stoppedTime)
    reel.start(angle: 17)
    close(reel.update(dt: scenario.dt, aspect: scenario.aspect)!.position.x, scenario.frames[0].position[0], "Restart begins at first shot")
    print("PASS: original 16 shots, two loops, dt=\(scenario.dt), portrait aspect=\(scenario.aspect)")
}
print("\(total) native animation frames match the original JavaScript")
