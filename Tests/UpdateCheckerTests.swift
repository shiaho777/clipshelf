import XCTest
@testable import ClipShelf

final class UpdateCheckerTests: XCTestCase {

    // MARK: - compareVersions

    func testCompareVersionsEqual() {
        XCTAssertEqual(UpdateReleaseParser.compareVersions("v1.1.1", "1.1.1"), 0)
        XCTAssertEqual(UpdateReleaseParser.compareVersions("1.1", "1.1.0"), 0)
        XCTAssertEqual(UpdateReleaseParser.compareVersions("1.0", "1.0"), 0)
    }

    func testCompareVersionsOrdering() {
        XCTAssertEqual(UpdateReleaseParser.compareVersions("v1.2.0", "1.1.9"), 1)
        XCTAssertEqual(UpdateReleaseParser.compareVersions("1.1.9", "v1.2.0"), -1)
        XCTAssertEqual(UpdateReleaseParser.compareVersions("1.10.0", "1.9.9"), 1)
        XCTAssertEqual(UpdateReleaseParser.compareVersions("2.0.0", "1.99.99"), 1)
        XCTAssertEqual(UpdateReleaseParser.compareVersions("1.0.0", "2.0.0"), -1)
    }

    // MARK: - pickDMGAsset

    func testPickDMGAssetChoosesDMGOverZIP() {
        let assets: [[String: Any]] = [
            ["name": "ClipShelf-2.0.0.zip", "browser_download_url": "https://x/zip", "size": Int64(1)],
            ["name": "ClipShelf-2.0.0.dmg", "browser_download_url": "https://x/dmg", "size": Int64(2)],
        ]
        let picked = UpdateReleaseParser.pickDMGAsset(assets)
        XCTAssertEqual(picked?.name, "ClipShelf-2.0.0.dmg")
        XCTAssertEqual(picked?.url, "https://x/dmg")
        XCTAssertEqual(picked?.size, 2)
    }

    func testPickDMGAssetPrefersUniversal() {
        let assets: [[String: Any]] = [
            ["name": "ClipShelf-arm64.dmg", "browser_download_url": "https://x/arm", "size": Int64(1)],
            ["name": "ClipShelf-universal.dmg", "browser_download_url": "https://x/univ", "size": Int64(2)],
        ]
        let picked = UpdateReleaseParser.pickDMGAsset(assets)
        XCTAssertEqual(picked?.name, "ClipShelf-universal.dmg")
    }

    func testPickDMGAssetReturnsNilWhenNone() {
        let assets: [[String: Any]] = [
            ["name": "ClipShelf.zip", "browser_download_url": "https://x/zip", "size": 1],
        ]
        XCTAssertNil(UpdateReleaseParser.pickDMGAsset(assets))
        XCTAssertNil(UpdateReleaseParser.pickDMGAsset([]))
    }

    // MARK: - parse

    func testParseReleasePayload() {
        let payload = """
        {
          "tag_name": "v2.0.0",
          "assets": [
            { "name": "ClipShelf-2.0.0.zip", "browser_download_url": "https://x/zip", "size": 100 },
            { "name": "ClipShelf-2.0.0.dmg", "browser_download_url": "https://x/dmg", "size": 2048 }
          ]
        }
        """.data(using: .utf8)!

        let release = UpdateReleaseParser.parse(payload)
        XCTAssertEqual(release?.version, "v2.0.0")
        XCTAssertEqual(release?.assetName, "ClipShelf-2.0.0.dmg")
        XCTAssertEqual(release?.assetURL.absoluteString, "https://x/dmg")
        XCTAssertEqual(release?.size, 2048)
    }

    func testParseRejectsMalformedPayload() {
        XCTAssertNil(UpdateReleaseParser.parse("not json".data(using: .utf8)!))
        XCTAssertNil(UpdateReleaseParser.parse(#"{"assets": []}"#.data(using: .utf8)!))
        let noDMG = #"{"tag_name":"v1.0.0","assets":[{"name":"a.zip","browser_download_url":"https://x","size":1}]}"#
        XCTAssertNil(UpdateReleaseParser.parse(noDMG.data(using: .utf8)!))
    }
}
