import XCTest
@testable import TokCatSources

final class FileTailTests: XCTestCase {
    func testOnlyCompleteLinesAreConsumed() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try "abc\ndef".data(using: .utf8)!.write(to: url)

        let tail = FileTail()
        XCTAssertEqual(tail.readNewLines(at: url), ["abc"])
        // 未换行的 "def" 不应被消费
        XCTAssertEqual(tail.offset, 4)

        try append("g\n", to: url)
        XCTAssertEqual(tail.readNewLines(at: url), ["defg"])
    }

    func testOffsetResetWhenFileShrinks() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try "aaaa\nbbbb\n".data(using: .utf8)!.write(to: url)

        let tail = FileTail()
        XCTAssertEqual(tail.readNewLines(at: url), ["aaaa", "bbbb"])
        XCTAssertEqual(tail.offset, 10)

        try "x\n".data(using: .utf8)!.write(to: url)
        XCTAssertEqual(tail.readNewLines(at: url), ["x"])
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: text.data(using: .utf8)!)
    }
}
