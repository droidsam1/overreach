import Foundation

public extension UUID {
    /// A deterministic UUID derived from `key`.
    ///
    /// Used for built-in catalog entries (the same exercise has the same id on every device and install) and
    /// for imports (importing the same file twice produces the same ids, so it can be de-duplicated).
    /// Not a cryptographic hash: never use it for anything security-related.
    static func stable(_ key: String) -> UUID {
        let bytes = Array(key.utf8)
        let first = fnv1a64(bytes, offsetBasis: 0xcbf2_9ce4_8422_2325)
        let second = fnv1a64(bytes.reversed(), offsetBasis: 0x8422_2325_cbf2_9ce4)

        var raw = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            raw[index] = UInt8(truncatingIfNeeded: first >> (index * 8))
            raw[8 + index] = UInt8(truncatingIfNeeded: second >> (index * 8))
        }
        raw[6] = (raw[6] & 0x0F) | 0x80  // version 8: custom, name-based
        raw[8] = (raw[8] & 0x3F) | 0x80  // RFC 4122 variant

        return UUID(uuid: (
            raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
            raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]
        ))
    }

    private static func fnv1a64<S: Sequence>(_ bytes: S, offsetBasis: UInt64) -> UInt64 where S.Element == UInt8 {
        var hash = offsetBasis
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
