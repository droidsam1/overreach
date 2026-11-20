import Foundation
import GarminImport

/// What was imported from Garmin, in Application Support. Health data stays on the device; the key is never here.
public actor FileGarminCache: GarminCacheStore {
    private let url: URL

    public init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        url = base.appendingPathComponent("Garmin", isDirectory: true).appendingPathComponent("cache.json")
    }

    public func load() -> GarminCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GarminCache.self, from: data)
    }

    public func save(_ cache: GarminCache) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(cache)
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url, options: .atomic)
            #endif
        } catch {
            // A cache that cannot be written only means the next launch asks Garmin again.
        }
    }
}
