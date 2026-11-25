import Foundation
import Security
import WeatherImport

public enum OpenWeather {
    public static func makeService() -> OpenWeatherService {
        OpenWeatherService(
            cacheFile: cacheFolder().appending(path: "cache.json"),
            readKey: { readKey() },
            writeKey: { try writeKey($0) },
            request: request
        )
    }

    static func cacheFolder() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "OverreachWeather")
    }

    static let request: @Sendable (URL) async -> OpenWeatherService.Response = { url in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        guard let (data, response) = try? await URLSession(configuration: configuration).data(from: url),
              let status = (response as? HTTPURLResponse)?.statusCode else { return .unavailable }
        switch status {
        case 200: return .data(data)
        case 401: return .rejected
        case 403, 429: return .backOff
        default: return .unavailable
        }
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
