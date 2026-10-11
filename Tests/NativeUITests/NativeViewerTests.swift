import XCTest
import UIKit

final class NativeViewerTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testNativeRenderingAndPhoneControls() throws {
        let app = XCUIApplication()
        app.launch()
        let preset = app.buttons["preset-menu"]
        XCTAssertTrue(preset.waitForExistence(timeout: 20))
        XCTAssertFalse(app.webViews.firstMatch.exists, "iOS must use the native Metal viewer")
        XCTAssertFalse(app.otherElements["renderer-error"].exists)
        assertControlsFit(app)
        // Confirm Metal drew the real red berry, rather than a blank canvas.
        let screenshot = app.screenshot()
        XCTAssertGreaterThan(redPixels(in: screenshot.image), 1000)
        attach(screenshot, name: "Native iPhone portrait")

        preset.tap()
        app.buttons["Lantern"].tap()
        XCTAssertTrue(preset.label.contains("Lantern"))
        app.buttons["reel-button"].tap()
        XCTAssertEqual(app.buttons["reel-button"].label, "Stop reel")
        assertControlsFit(app)
        attach(app.screenshot(), name: "Original native reel playback")
        app.buttons["reel-button"].tap()
        XCTAssertTrue(preset.label.contains("Lantern"), "Stopping the original reel must restore the chosen look")
        app.buttons["adjust-button"].tap()
        XCTAssertTrue(app.navigationBars["Adjust"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["Key light"].exists)
        app.sliders["Key light"].adjust(toNormalizedSliderPosition: 0.4)
        attach(app.screenshot(), name: "Native adjustment sheet")
        app.buttons["Done"].tap()
    }

    private func assertControlsFit(_ app: XCUIApplication) {
        let screen = app.frame
        for id in ["preset-menu", "reel-button", "adjust-button"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.isHittable, id)
            XCTAssertGreaterThanOrEqual(button.frame.minX, screen.minX, id)
            XCTAssertLessThanOrEqual(button.frame.maxX, screen.maxX, id)
            XCTAssertGreaterThanOrEqual(button.frame.minY, screen.minY, id)
            XCTAssertLessThanOrEqual(button.frame.maxY, screen.maxY, id)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, id)
        }
    }
    func testBacklitAndCloserZoom() throws {
        let app = XCUIApplication()
        app.launch()
        let preset = app.buttons["preset-menu"]
        XCTAssertTrue(preset.waitForExistence(timeout: 20))
        preset.tap()
        app.buttons["Backlit"].tap()
        XCTAssertTrue(preset.label.contains("Backlit"))
        let before = app.screenshot()
        XCTAssertGreaterThan(brightPixels(in: before.image), 10000, "Original Backlit uses a pale background")
        let beforeRed = redPixels(in: before.image)
        attach(before, name: "Restored Backlit")
        let canvas = app.otherElements["berry-canvas"]
        canvas.pinch(withScale: 4, velocity: 3)
        let zoomed = app.screenshot()
        XCTAssertGreaterThan(redPixels(in: zoomed.image), Int(Double(beforeRed) * 1.4), "Native pinch must magnify the berry substantially")
        XCTAssertFalse(app.otherElements["renderer-error"].exists)
        attach(zoomed, name: "Native close-up pinch zoom")
        canvas.doubleTap()
    }
    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func redPixels(in image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let width = 220, height = 480
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            var count = 0
            let data = bytes.bindMemory(to: UInt8.self)
            for y in 80..<400 {
                for x in 20..<200 {
                    let i = (y * width + x) * 4
                    if data[i] > 50 && Int(data[i]) > Int(data[i+1]) * 2 && Int(data[i]) > Int(data[i+2]) * 2 { count += 1 }
                }
            }
            return count
        }
    }
    private func brightPixels(in image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let width = 220, height = 480
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            let data = bytes.bindMemory(to: UInt8.self)
            return (80..<400).reduce(0) { count, y in
                count + (20..<200).filter { x in
                    let i = (y * width + x) * 4
                    return data[i] > 230 && data[i+1] > 230 && data[i+2] > 230
                }.count
            }
        }
    }
}
