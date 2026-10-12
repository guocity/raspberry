import Foundation
import CoreGraphics

for drawable in [CGSize(width: 1179, height: 2556), CGSize(width: 1290, height: 2796),
                 CGSize(width: 2048, height: 2732), CGSize(width: 640, height: 480)] {
    precondition(BerryRenderQuality.sceneSize(drawable: drawable, fast: false) == drawable)
    let fast = BerryRenderQuality.sceneSize(drawable: drawable, fast: true)
    precondition(max(fast.width, fast.height) <= 1600)
    precondition(fast.width * fast.height <= drawable.width * drawable.height * 0.5)
    precondition(abs(fast.width / fast.height - drawable.width / drawable.height) < 0.003)
}
precondition(BerryRenderQuality.sceneSize(drawable: .zero, fast: true) == CGSize(width: 1, height: 1))
print("PASS: full detail, pixel budget, long-edge cap, aspect ratio, zero-size guard")
