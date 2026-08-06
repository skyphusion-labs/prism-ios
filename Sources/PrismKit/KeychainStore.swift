import Foundation

/// Small Keychain / memory secret store for device keys.
///
/// On Apple platforms values go in the Keychain (kSecClassGenericPassword).
/// On Linux CI (no Security framework) values stay in-process memory so unit
/// tests still exercise the API surface.
public protocol SecretStore: Sendable {
  func get(_ key: String) throws -> String?
  func set(_ value: String?, for key: String) throws
}

public enum SecretStoreKeys {
  /// Control-plane device key (`pcp_…`).
  public static let controlPlaneDeviceKey = "org.skyphusion.prism.control-plane.device-key"
  public static let controlPlaneBaseURL = "org.skyphusion.prism.control-plane.base-url"
  public static let playgroundBaseURL = "org.skyphusion.prism.playground.base-url"
  public static let backendMode = "org.skyphusion.prism.backend-mode"
  /// Playground session token value (cookie `__Host-prism_session`).
  public static let playgroundSessionCookie = "org.skyphusion.prism.playground.session-cookie"
  public static let playgroundSessionUsername = "org.skyphusion.prism.playground.session-username"
  /// UI prefs (model picks, stream, filters) -- non-secret but Keychain keeps one store.
  public static let selectedChatModel = "org.skyphusion.prism.pref.chat-model"
  public static let selectedImageModel = "org.skyphusion.prism.pref.image-model"
  public static let selectedVideoModel = "org.skyphusion.prism.pref.video-model"
  public static let selectedSpeechModel = "org.skyphusion.prism.pref.speech-model"
  public static let selectedSttModel = "org.skyphusion.prism.pref.stt-model"
  public static let selectedMusicModel = "org.skyphusion.prism.pref.music-model"
  public static let useStream = "org.skyphusion.prism.pref.use-stream"
  public static let hideUnspendable = "org.skyphusion.prism.pref.hide-unspendable"
  /// Require Face ID / Touch ID when opening the app with a stored device key.
  public static let biometricLockEnabled = "org.skyphusion.prism.pref.biometric-lock"
  /// In-flight async plane job ids (survive lock / Task cancel so we can resume poll).
  public static let pendingMusicJobId = "org.skyphusion.prism.job.music.id"
  public static let pendingMusicJobModel = "org.skyphusion.prism.job.music.model"
  public static let pendingVideoJobId = "org.skyphusion.prism.job.video.id"
  public static let pendingVideoJobModel = "org.skyphusion.prism.job.video.model"
  public static let pendingSpeechJobId = "org.skyphusion.prism.job.speech.id"
  public static let pendingSpeechJobModel = "org.skyphusion.prism.job.speech.model"
  /// App Group key for widget balance (UserDefaults suite, not Keychain).
  public static let appGroupId = "group.org.skyphusion.prism"
  public static let widgetBalanceKey = "widget.balance"
  public static let widgetUpdatedAtKey = "widget.updatedAt"
}

/// In-memory store (tests + Linux).
public final class MemorySecretStore: SecretStore, @unchecked Sendable {
  private var bag: [String: String] = [:]
  private let lock = NSLock()

  public init() {}

  public func get(_ key: String) throws -> String? {
    lock.lock(); defer { lock.unlock() }
    return bag[key]
  }

  public func set(_ value: String?, for key: String) throws {
    lock.lock(); defer { lock.unlock() }
    if let value { bag[key] = value } else { bag.removeValue(forKey: key) }
  }
}

#if canImport(Security)
import Security

/// Keychain-backed store (iOS / macOS).
public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
  public let service: String

  public init(service: String = "org.skyphusion.prism") {
    self.service = service
  }

  public func get(_ key: String) throws -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else {
      throw PrismError.transport("Keychain read failed (\(status))")
    }
    guard let data = item as? Data, let s = String(data: data, encoding: .utf8) else {
      throw PrismError.transport("Keychain item was not UTF-8 text")
    }
    return s
  }

  public func set(_ value: String?, for key: String) throws {
    let deleteQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
    SecItemDelete(deleteQuery as CFDictionary)
    guard let value else { return }
    guard let data = value.data(using: .utf8) else {
      throw PrismError.transport("Keychain value was not UTF-8")
    }
    let add: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = SecItemAdd(add as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw PrismError.transport("Keychain write failed (\(status))")
    }
  }
}

public enum SecretStores {
  /// Default production store (Keychain on Apple, memory elsewhere).
  public static func `default`() -> any SecretStore {
    KeychainSecretStore()
  }
}
#else
public enum SecretStores {
  public static func `default`() -> any SecretStore {
    MemorySecretStore()
  }
}
#endif
