import Foundation
import Security
import WeatherImport

public enum OpenWeather {
    public static func makeService() -> OpenWeatherService {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let cache = root.appending(path: "OverreachWeather").appending(path: "cache.json")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: configuration)
        return OpenWeatherService(
            cacheFile: cache,
            readKey: { readKey() },
            writeKey: { try writeKey($0) },
            request: { url in
                guard let (data, response) = try? await session.data(from: url),
                      (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                return data
            }
        )
    }

    private static func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.overreach.openweather",
            kSecAttrAccount as String: "personal-api-key",
        ]
    }

    private static func readKey() -> String? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKey(_ key: String?) throws {
        let query = keychainQuery()
        let status: OSStatus
        if let key {
            let value = Data(key.utf8)
            let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
            if update == errSecItemNotFound {
                var item = query
                item[kSecValueData as String] = value
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                status = SecItemAdd(item as CFDictionary, nil)
            } else {
                status = update
            }
        } else {
            status = SecItemDelete(query as CFDictionary)
        }
        guard status == errSecSuccess || (key == nil && status == errSecItemNotFound) else {
            throw KeychainError()
        }
    }

    private struct KeychainError: Error {}
}
