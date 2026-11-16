import Foundation
import LocalAuthentication
import os

@MainActor
final class BiometricAuthService {
    static let shared = BiometricAuthService()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ClipShelf",
        category: "BiometricAuth"
    )

    private var sessionUnlockExpiry: Date?
    static let sessionUnlockDuration: TimeInterval = 300

    private init() {}

    var isSessionUnlocked: Bool {
        guard let expiry = sessionUnlockExpiry else { return false }
        return Date() < expiry
    }

    func authenticateForSession(reason: String) async throws {
        if isSessionUnlocked { return }
        try await authenticate(reason: reason)
        sessionUnlockExpiry = Date().addingTimeInterval(Self.sessionUnlockDuration)
    }

    func lockSession() {
        sessionUnlockExpiry = nil
    }

    func authenticate(reason: String) async throws {
        let context = LAContext()
        var policyError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            let error = policyError ?? NSError(
                domain: LAErrorDomain,
                code: LAError.biometryNotAvailable.rawValue,
                userInfo: nil
            )
            logger.warning("Device authentication unavailable: \(error.localizedDescription)")
            throw error
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            ) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: LAError(.authenticationFailed))
                }
            }
        }
    }

    var isBiometryAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }
}
