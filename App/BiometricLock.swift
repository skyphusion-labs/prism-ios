import Foundation
import LocalAuthentication
import PrismKit
import Security

/// Face ID / Touch ID gate for the enrolled control-plane session.
enum BiometricLock {
  static let prefKey = SecretStoreKeys.biometricLockEnabled

  static var biometryLabel: String {
    let ctx = LAContext()
    _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    switch ctx.biometryType {
    case .faceID: return "Face ID"
    case .touchID: return "Touch ID"
    case .opticID: return "Optic ID"
    default: return "Device passcode"
    }
  }

  static func isAvailable() -> Bool {
    let ctx = LAContext()
    var err: NSError?
    return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
      || ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err)
  }

  /// Unlock with biometrics, falling back to device passcode.
  static func authenticate(reason: String) async -> Bool {
    let ctx = LAContext()
    ctx.localizedCancelTitle = "Cancel"
    var err: NSError?
    let policy: LAPolicy =
      ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
      ? .deviceOwnerAuthenticationWithBiometrics
      : .deviceOwnerAuthentication
    return await withCheckedContinuation { cont in
      ctx.evaluatePolicy(policy, localizedReason: reason) { ok, _ in
        cont.resume(returning: ok)
      }
    }
  }
}
