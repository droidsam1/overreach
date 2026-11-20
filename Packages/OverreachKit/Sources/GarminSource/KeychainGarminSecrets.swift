import Foundation
import GarminImport
#if canImport(Security)
import Security
#endif

/// The Garmin key and token in the iOS Keychain, encrypted with keys the Secure Enclave protects (ADR-0022).
///
/// - The key is `kSecAttrSynchronizable`, `AfterFirstUnlock`: it survives app updates, re-signing, deleting and
///   reinstalling the app, and comes back on a new iPhone through the person's own iCloud Keychain (end-to-end
///   encrypted). Without iCloud Keychain it stays on this device.
/// - The 24 h token is `ThisDeviceOnly` and never synchronised: minting another one is cheap.
public struct KeychainGarminSecrets: GarminSecretStore {
    private let service: String

    public init(service: String = "app.overreach.garmin") {
        self.service = service
    }

    private enum Item: String {
        case key = "personal-api-key"
        case token = "access-token"

        var synchronizable: Bool { self == .key }
    }

    public func loadKey() async -> GarminStoredKey? {
        read(.key).flatMap { try? JSONDecoder().decode(GarminStoredKey.self, from: $0) }
    }

    public func saveKey(_ key: GarminStoredKey) async throws {
        try write(.key, JSONEncoder().encode(key))
    }

    public func loadToken() async -> GarminToken? {
        read(.token).flatMap { try? JSONDecoder().decode(GarminToken.self, from: $0) }
    }

    public func saveToken(_ token: GarminToken?) async {
        guard let token, let data = try? JSONEncoder().encode(token) else {
            delete(.token)
            return
        }
        try? write(.token, data)
    }

    public func deleteAll() async {
        delete(.key)
        delete(.token)
    }

    // MARK: Keychain

    public struct KeychainError: Error {
        public let status: Int32
    }

    #if canImport(Security)
    private func query(_ item: Item) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue,
            // Finds the item whether it is synchronised or not (e.g. saved before iCloud Keychain was turned on).
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
    }

    private func read(_ item: Item) -> Data? {
        var query = query(item)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func write(_ item: Item, _ data: Data) throws {
        delete(item)
        var attributes = query(item)
        attributes[kSecAttrSynchronizable as String] = item.synchronizable
        attributes[kSecAttrAccessible as String] = item.synchronizable
            ? kSecAttrAccessibleAfterFirstUnlock
            : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if item == .key {
            attributes[kSecAttrLabel as String] = "Overreach – Garmin Personal API key"
        }
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    private func delete(_ item: Item) {
        SecItemDelete(query(item) as CFDictionary)
    }
    #else
    // Linux builds (CI for pure modules) have no Keychain: nothing is stored.
    private func read(_ item: Item) -> Data? { nil }
    private func write(_ item: Item, _ data: Data) throws { throw KeychainError(status: -1) }
    private func delete(_ item: Item) {}
    #endif
}
