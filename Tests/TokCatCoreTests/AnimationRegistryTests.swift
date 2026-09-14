#if canImport(AppKit)
import XCTest
import AppKit
@testable import TokCatCore

final class AnimationRegistryTests: XCTestCase {
    func testRegistryRegistersAndLooksUp() {
        let registry = AnimationRegistry()
        let pack = TestAnimationPack(identifier: "a.pack", displayName: "A")
        registry.register(pack)
        XCTAssertNotNil(registry.pack(identifier: "a.pack"))
        XCTAssertEqual(registry.defaultPack?.identifier, "a.pack")
    }

    func testDefaultPackIsFirstWhenEmpty() {
        XCTAssertNil(AnimationRegistry().defaultPack)
    }

    func testLoadExternalPackFromTempDirectory() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let packDir = root.appendingPathComponent("cat-hd")
        try fm.createDirectory(at: packDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let manifest = """
        { "id": "cat-hd", "displayName": "Cat HD", "frames": ["00.png"], "idleFPS": 2, "maxFPS": 20 }
        """
        try manifest.data(using: .utf8)!.write(to: packDir.appendingPathComponent("manifest.json"))

        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 32, height: 32)).fill()
        image.unlockFocus()
        let png = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let data = try XCTUnwrap(png.representation(using: .png, properties: [:]))
        try data.write(to: packDir.appendingPathComponent("00.png"))

        let registry = AnimationRegistry()
        let loaded = registry.loadExternalPacks(from: root)
        XCTAssertEqual(loaded, 1)
        let pack = try XCTUnwrap(registry.pack(identifier: "cat-hd"))
        XCTAssertEqual(pack.displayName, "Cat HD")
        XCTAssertNotNil(pack.image(frameIndex: 0, height: 18))
    }

    func testInvalidExternalPackageIgnored() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root.appendingPathComponent("broken"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let registry = AnimationRegistry()
        XCTAssertEqual(registry.loadExternalPacks(from: root), 0)
    }
}
#endif
