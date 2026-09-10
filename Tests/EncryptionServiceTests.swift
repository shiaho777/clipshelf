import XCTest
@testable import ClipShelf

final class EncryptionServiceTests: XCTestCase {

    private let service = EncryptionService.shared

    func testStringRoundtrip() throws {
        let plaintext = "Hello, World! 🔐"
        let encrypted = try service.encryptString(plaintext)
        let decrypted = try service.decryptToString(encrypted)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testDataRoundtrip() throws {
        let data = Data("binary \0 data \n test".utf8)
        let encrypted = try service.encrypt(data)
        let decrypted = try service.decrypt(encrypted)
        XCTAssertEqual(decrypted, data)
    }

    func testEmptyStringRoundtrip() throws {
        let encrypted = try service.encryptString("")
        let decrypted = try service.decryptToString(encrypted)
        XCTAssertEqual(decrypted, "")
    }

    func testUnicodeRoundtrip() throws {
        let unicode = String(repeating: "こんにちは🗂️", count: 50)
        let encrypted = try service.encryptString(unicode)
        let decrypted = try service.decryptToString(encrypted)
        XCTAssertEqual(decrypted, unicode)
    }

    func testEncryptedDiffersFromPlaintext() throws {
        let plaintext = "sensitive data"
        let encrypted = try service.encryptString(plaintext)
        XCTAssertNotEqual(String(data: encrypted, encoding: .utf8), plaintext)
    }

    func testNonDeterministicEncryption() throws {
        let plaintext = "same input"
        let enc1 = try service.encryptString(plaintext)
        let enc2 = try service.encryptString(plaintext)
        XCTAssertNotEqual(enc1, enc2, "Each encryption must use a distinct nonce")
    }

    func testEncryptedLengthExceedsPlaintext() throws {
        let plaintext = "hello"
        let encrypted = try service.encryptString(plaintext)
        XCTAssertGreaterThan(encrypted.count, plaintext.utf8.count)
    }

    func testDecryptInvalidDataThrows() {
        XCTAssertThrowsError(try service.decrypt(Data("garbage".utf8)))
    }

    func testDecryptTruncatedBlobThrows() throws {
        let encrypted = try service.encrypt(Data("hello".utf8))
        let truncated = encrypted.prefix(8)
        XCTAssertThrowsError(try service.decrypt(Data(truncated)))
    }

    func testDecryptBitFlipThrows() throws {
        var encrypted = try service.encrypt(Data("hello world".utf8))
        if encrypted.count > 15 {
            encrypted[13] ^= 0xFF
        }
        XCTAssertThrowsError(try service.decrypt(encrypted))
    }
}
