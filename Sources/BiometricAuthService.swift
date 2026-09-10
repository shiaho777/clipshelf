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

    private init() {}

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
