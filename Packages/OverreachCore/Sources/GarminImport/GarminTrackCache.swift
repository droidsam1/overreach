import Domain
import Foundation

/// Compact, local-only decoded FIT data. Only running measurements needed by analytics are retained.
struct GarminTrackCache: Codable, Hashable, Sendable {
    private let compressed: Data?
    private let originalSize: Int?
    let retryAfter: Date?

    // A cap on both sides keeps the cache usable on small devices and protects old/untrusted files on load.
    private static let maximumBytes = 16 * 1_024 * 1_024
    private static let maximumCompressedBytes = 512 * 1_024

    init?(track: RunningTrack) {
        guard let data = try? JSONEncoder().encode(track), data.count <= Self.maximumBytes,
              let compressed = ZlibData.compress(data), compressed.count <= Self.maximumCompressedBytes else {
            return nil
        }
        self.compressed = compressed
        originalSize = data.count
        retryAfter = nil
    }

    init(retryAfter: Date) {
        compressed = nil
        originalSize = nil
        self.retryAfter = retryAfter
    }

    var track: RunningTrack? {
        guard let compressed, compressed.count <= Self.maximumCompressedBytes, let originalSize,
              (1...Self.maximumBytes).contains(originalSize),
              let data = ZlibData.inflate(compressed, size: originalSize) else { return nil }
        return try? JSONDecoder().decode(RunningTrack.self, from: data)
    }

    func needsDownload(at date: Date) -> Bool {
        retryAfter.map { $0 <= date } ?? (compressed == nil)
    }
}
