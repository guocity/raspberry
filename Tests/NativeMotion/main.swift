import Foundation
import simd

let identity = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
func check(_ actual: simd_quatf, _ expected: simd_quatf) {
    precondition(abs(simd_dot(actual.vector, expected.vector)) > 0.99999)
}
let reference = simd_quatf(angle: 1.2, axis: simd_normalize(SIMD3<Float>(1, 2, 3)))
check(BerryMotionRotation.relative(reference: reference, attitude: reference,
    rotationRate: .zero, sampleAge: 0), identity)
for axis in [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, 1)] {
    for angle: Float in [-3.14, -1, 0, 1, 3.14] {
        let turn = simd_quatf(angle: angle, axis: axis)
        check(BerryMotionRotation.relative(reference: reference, attitude: reference * turn,
            rotationRate: .zero, sampleAge: 0), turn)
    }
    check(BerryMotionRotation.relative(reference: identity, attitude: identity,
        rotationRate: axis * 2, sampleAge: 0.01), simd_quatf(angle: 0.02, axis: axis))
    check(BerryMotionRotation.relative(reference: identity, attitude: identity,
        rotationRate: axis * 2, sampleAge: 10), simd_quatf(angle: 0.04, axis: axis))
    check(BerryMotionRotation.relative(reference: identity, attitude: identity,
        rotationRate: axis * 2, sampleAge: -1), identity)
}
print("PASS: recenter, all three axes, direct response, bounded prediction, stale timestamps")

for direction in [SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, -1, 0),
                  SIMD3<Float>(1, 2, 3), SIMD3<Float>(-1, -2, -3)] {
    let pose = BerryMotionRotation.upright(direction: direction)
    precondition(pose.up.y > 0.17, "The berry must remain upright even at the poles")
    precondition(abs(simd_dot(pose.direction, pose.up)) < 0.00001)
    precondition(abs(simd_length(pose.direction) - 1) < 0.00001)
}
for angle: Float in [-3.14, -1, 0, 1, 3.14] {
    let roll = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 0, 1))
    let pose = BerryMotionRotation.upright(direction: roll.act(SIMD3(0, 0, 1)))
    precondition(simd_distance(pose.direction, SIMD3(0, 0, 1)) < 0.00001)
    precondition(simd_distance(pose.up, SIMD3(0, 1, 0)) < 0.00001, "Phone roll must not roll the berry")
}
print("PASS: upright world-up camera, ignored roll, bounded elevation, pole stability")
