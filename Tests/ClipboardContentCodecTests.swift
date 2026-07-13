import XCTest
@testable import ClipShelf

final class ClipboardContentCodecTests: XCTestCase {
    func testEncodeFilePathsAsJSONArray() throws {
        let encoded = ClipboardContentCodec.encodeFilePaths(["/tmp/a", "/tmp/b"])
        let data = try XCTUnwrap(encoded.data(using: .utf8))
        let decoded = try JSONDecoder().decode([String].self, from: data)
        XCTAssertEqual(decoded, ["/tmp/a", "/tmp/b"])
    }
}
