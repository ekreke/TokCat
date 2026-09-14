import XCTest
import AppKit
@testable import TokCatCore

final class CatRenderingTests: XCTestCase {
    func testCatImageHasVisiblePixels() throws {
        let pack = BuiltinCatPack()
        let image = try XCTUnwrap(pack.image(frameIndex: 0, height: 18))
        let rep = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))

        var opaque = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.1 {
                    opaque += 1
                }
            }
        }
        XCTAssertGreaterThan(opaque, 0, "猫图完全不透明像素为 0，说明绘制失败")
        print("cat image \(rep.pixelsWide)x\(rep.pixelsHigh), opaque pixels = \(opaque)")
    }

    func testFramesDiffer() throws {
        let pack = BuiltinCatPack()
        let a = try XCTUnwrap(pack.image(frameIndex: 0, height: 18)?.tiffRepresentation)
        let b = try XCTUnwrap(pack.image(frameIndex: 3, height: 18)?.tiffRepresentation)
        XCTAssertNotEqual(a, b, "不同帧的渲染结果相同，动画不会有变化")
    }

    func testConsecutiveFramesHaveVisibleMotion() throws {
        let pack = BuiltinCatPack()
        let diff = try pixelDifference(
            try XCTUnwrap(pack.image(frameIndex: 0, height: 32)),
            try XCTUnwrap(pack.image(frameIndex: 2, height: 32))
        )
        XCTAssertGreaterThan(diff, 15, "相邻帧差异过小，视觉上近似静止")
    }

    private func pixelDifference(_ a: NSImage, _ b: NSImage) throws -> Int {
        let ra = try XCTUnwrap(a.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let rb = try XCTUnwrap(b.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var diff = 0
        for y in 0..<min(ra.pixelsHigh, rb.pixelsHigh) {
            for x in 0..<min(ra.pixelsWide, rb.pixelsWide) {
                let ca = ra.colorAt(x: x, y: y)?.alphaComponent ?? 0
                let cb = rb.colorAt(x: x, y: y)?.alphaComponent ?? 0
                if abs(ca - cb) > 0.3 { diff += 1 }
            }
        }
        return diff
    }
}
