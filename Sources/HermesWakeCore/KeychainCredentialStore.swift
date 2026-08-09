import Foundation
import Security

public protocol CredentialStoring: Sendable {
  func password(for account: String) throws -> String?
  func save(password: String, for account: String) throws
  func deletePassword(for account: String) throws
}

public struct KeychainCredentialStore: CredentialStoring {
  public let service: String

  public init(service: String = "ai.hermes.wake.remote") {
    self.service = service
  }

  public func password(for account: String) throws -> String? {
    var query = baseQuery(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw KeychainError.status(status)
    }
    return String(data: data, encoding: .utf8)
  }

  public func save(password: String, for account: String) throws {
    let data = Data(password.utf8)
    let query = baseQuery(account: account)
    let status = SecItemUpdate(
      query as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    if status == errSecItemNotFound {
      var item = query
      item[kSecValueData as String] = data
      let addStatus = SecItemAdd(item as CFDictionary, nil)
      guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
    } else if status != errSecSuccess {
      throw KeychainError.status(status)
    }
  }

  public func deletePassword(for account: String) throws {
    let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.status(status)
    }
  }

  private func baseQuery(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}

public enum KeychainError: LocalizedError {
  case status(OSStatus)

  public var errorDescription: String? {
    switch self {
    case .status(let status):
      return SecCopyErrorMessageString(status, nil) as String?
        ?? "Keychain operation failed with status \(status)."
    }
  }
}
