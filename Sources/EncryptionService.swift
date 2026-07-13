import Foundation
import CryptoKit
import Security
import os

/// AES-256-GCM encryption service for sensitive clipboard content.
/// The 256-bit symmetric key is generated once and stored in the macOS Keychain
/// with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — it never leaves the device.
final class EncryptionService {
    static let shared = EncryptionService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipboardManager",
                                category: "Encryption")
    private let keychainService = "com.clipboardmanager.encryption"
    private let keychainAccount = "masterKey-v1"

    // Lazy init: loaded from Keychain on first use, not at app start.
    private lazy var _key: SymmetricKey = loadOrCreateKey()
    private var key: SymmetricKey { _key }

    private init() {}

    // MARK: - Public API

    /// Encrypt `data` using AES-256-GCM. Returns the combined nonce+ciphertext+tag blob.
    func encrypt(_ data: Data) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw EncryptionError.sealFailed
        }
        return combined
    }

    /// Decrypt a combined nonce+ciphertext+tag blob produced by `encrypt(_:)`.
    func decrypt(_ combined: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - String Convenience

    func encryptString(_ string: String) throws -> Data {
        guard let data = string.data(using: .utf8) else {
            throw EncryptionError.encodingFailed
        }
        return try encrypt(data)
    }

    func decryptToString(_ combined: Data) throws -> String {
        let data = try decrypt(combined)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncryptionError.decodingFailed
        }
        return string
    }

    // MARK: - Key Management

    private func loadOrCreateKey() -> SymmetricKey {
        if let data = loadFromKeychain() {
            guard data.count == 32 else {
                logger.warning("Keychain key has unexpected size \(data.count); regenerating")
                return createAndSaveKey()
            }
            return SymmetricKey(data: data)
        }
        return createAndSaveKey()
    }

    private func createAndSaveKey() -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let saved = saveToKeychain(keyData)
        if !saved {
            logger.error("Failed to persist encryption key to Keychain — key is ephemeral this session")
        }
        return key
    }

    private func loadFromKeychain() -> Data? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService as CFString,
            kSecAttrAccount: keychainAccount as CFString,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    private func saveToKeychain(_ keyData: Data) -> Bool {
        let attributes: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      keychainService as CFString,
            kSecAttrAccount:      keychainAccount as CFString,
            kSecValueData:        keyData,
            kSecAttrAccessible:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [CFString: Any] = [kSecValueData: keyData]
            let query: [CFString: Any] = [
                kSecClass:       kSecClassGenericPassword,
                kSecAttrService: keychainService as CFString,
                kSecAttrAccount: keychainAccount as CFString,
            ]
            status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        }
        return status == errSecSuccess
    }
}

// MARK: - Errors

enum EncryptionError: LocalizedError {
    case sealFailed
    case encodingFailed
    case decodingFailed
    case keyUnavailable

    var errorDescription: String? {
        switch self {
        case .sealFailed:     return "AES-GCM seal produced no combined output"
        case .encodingFailed: return "Failed to encode string as UTF-8"
        case .decodingFailed: return "Failed to decode decrypted bytes as UTF-8"
        case .keyUnavailable: return "Encryption key is unavailable"
        }
    }
}
