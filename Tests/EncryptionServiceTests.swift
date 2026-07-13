import XCTest
@testable import ClipShelf

final class EncryptionServiceTests: XCTestCase {

    private let service = EncryptionService.shared

    // MARK: - Roundtrip

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

    // MARK: - Security properties

    func testEncryptedDiffersFromPlaintext() throws {
        let plaintext = "sensitive data"
        let encrypted = try service.encryptString(plaintext)
        // The raw encrypted blob should not be decodable as the original UTF-8
        XCTAssertNotEqual(String(data: encrypted, encoding: .utf8), plaintext)
    }

    func testNonDeterministicEncryption() throws {
        // AES-GCM uses a fresh random nonce each call → two encryptions must differ
        let plaintext = "same input"
        let enc1 = try service.encryptString(plaintext)
        let enc2 = try service.encryptString(plaintext)
        XCTAssertNotEqual(enc1, enc2, "Each encryption must use a distinct nonce")
    }

    func testEncryptedLengthExceedsPlaintext() throws {
        let plaintext = "hello"
        let encrypted = try service.encryptString(plaintext)
        // AES-GCM output = nonce (12 B) + ciphertext + tag (16 B) > plaintext
        XCTAssertGreaterThan(encrypted.count, plaintext.utf8.count)
    }

    // MARK: - Error handling

    func testDecryptInvalidDataThrows() {
        XCTAssertThrowsError(try service.decrypt(Data("garbage".utf8)))
    }

    func testDecryptTruncatedBlobThrows() throws {
        let encrypted = try service.encrypt(Data("hello".utf8))
        // Truncate to an invalid length
        let truncated = encrypted.prefix(8)
        XCTAssertThrowsError(try service.decrypt(Data(truncated)))
    }

    func testDecryptBitFlipThrows() throws {
        var encrypted = try service.encrypt(Data("hello world".utf8))
        // Flip a bit in the ciphertext (after the 12-byte nonce)
        if encrypted.count > 15 {
            encrypted[13] ^= 0xFF
        }
        XCTAssertThrowsError(try service.decrypt(encrypted))
    }
}
