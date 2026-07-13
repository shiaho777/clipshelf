import Foundation
import LocalAuthentication
import os

/// Wraps `LAContext` for async/await Touch ID / Face ID / password authentication.
/// Uses `.deviceOwnerAuthentication` so biometry failure falls back to the system
/// password, preventing lockout when Touch ID is unavailable (wet fingers, locked, etc.).
@MainActor
final class BiometricAuthService {
    static let shared = BiometricAuthService()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ClipboardManager",
        category: "BiometricAuth"
    )

    private init() {}

    // MARK: - Public API

    /// Authenticate with Touch ID / Face ID, falling back to the login password.
    ///
    /// - Parameter reason: Localised reason string shown in the authentication prompt.
    /// - Throws: An `LAError` if authentication fails or is cancelled by the user.
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

    /// Returns whether device owner authentication (biometry or password) is available.
    var isBiometryAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }
}
