import Domain
import Foundation

/// Reads the ZIP envelope from the official original-activity download without extracting anything to disk.
enum GarminFITArchive {
    private static let maximumFITBytes = 16 * 1_024 * 1_024
    private static let maximumArchiveBytes = 8 * 1_024 * 1_024

    enum ArchiveError: Error {
        case invalidArchive, invalidFIT
    }

    static func track(from data: Data) throws -> RunningTrack {
        let fit: Data
        if data.count >= 12, data.dropFirst(8).prefix(4).elementsEqual(".FIT".utf8) {
            fit = data
        } else {
            guard data.count <= maximumArchiveBytes else { throw ArchiveError.invalidArchive }
            fit = try Zip(data).fit()
        }
        let track = try GarminFIT.decode(fit)
        guard !track.samples.isEmpty else { throw ArchiveError.invalidFIT }
        return track
    }

    private struct Entry {
        let name: [UInt8]
        let method: Int
        let checksum: UInt32
        let compressedSize: Int
        let size: Int
        let offset: Int
    }

    private struct Zip {
        let bytes: [UInt8]

        init(_ data: Data) { bytes = Array(data) }

        func fit() throws -> Data {
            let end = try directoryEnd()
            let count = try value(at: end + 10, count: 2)
            let size = try value(at: end + 12, count: 4)
            let start = try value(at: end + 16, count: 4)
            guard (1...128).contains(count), start + size == end else { throw ArchiveError.invalidArchive }

            var cursor = start
            var entries: [Entry] = []
            for _ in 0..<count {
                guard try value(at: cursor, count: 4) == 0x02014B50, cursor + 46 <= end else {
                    throw ArchiveError.invalidArchive
                }
                let nameSize = try value(at: cursor + 28, count: 2)
                let extra = try value(at: cursor + 30, count: 2)
                let comment = try value(at: cursor + 32, count: 2)
                let nameStart = cursor + 46
                let next = nameStart + nameSize + extra + comment
                guard next <= end else { throw ArchiveError.invalidArchive }
                let name = Array(bytes[nameStart..<nameStart + nameSize])
                if String(bytes: name, encoding: .utf8)?.lowercased().hasSuffix(".fit") == true {
                    entries.append(try entry(at: cursor, name: name))
                }
                cursor = next
            }
            guard cursor == end, entries.count == 1, let entry = entries.first else {
                throw ArchiveError.invalidArchive
            }
            return try unpack(entry, before: start)
        }

        private func directoryEnd() throws -> Int {
            let last = bytes.count - 22
            guard last >= 0 else { throw ArchiveError.invalidArchive }
            for index in stride(from: last, through: max(0, last - 65_535), by: -1) {
                guard try value(at: index, count: 4) == 0x06054B50,
                      try value(at: index + 20, count: 2) == last - index else { continue }
                guard try value(at: index + 4, count: 4) == 0,
                      try value(at: index + 8, count: 2) == value(at: index + 10, count: 2)
                else { throw ArchiveError.invalidArchive }
                return index
            }
            throw ArchiveError.invalidArchive
        }

        private func entry(at start: Int, name: [UInt8]) throws -> Entry {
            let flags = try value(at: start + 8, count: 2)
            let method = try value(at: start + 10, count: 2)
            let size = try value(at: start + 24, count: 4)
            guard (flags & 1) == 0, [0, 8].contains(method), (1...GarminFITArchive.maximumFITBytes).contains(size),
                  try value(at: start + 34, count: 2) == 0 else { throw ArchiveError.invalidArchive }
            return Entry(
                name: name, method: method, checksum: UInt32(try value(at: start + 16, count: 4)),
                compressedSize: try value(at: start + 20, count: 4), size: size,
                offset: try value(at: start + 42, count: 4)
            )
        }

        private func unpack(_ entry: Entry, before end: Int) throws -> Data {
            let offset = entry.offset
            guard offset + 30 <= end, try value(at: offset, count: 4) == 0x04034B50,
                  try value(at: offset + 6, count: 2) & 1 == 0,
                  try value(at: offset + 8, count: 2) == entry.method else { throw ArchiveError.invalidArchive }
            let nameStart = offset + 30
            let nameEnd = nameStart + (try value(at: offset + 26, count: 2))
            let payload = nameEnd + (try value(at: offset + 28, count: 2))
            guard payload + entry.compressedSize <= end, bytes[nameStart..<nameEnd].elementsEqual(entry.name) else {
                throw ArchiveError.invalidArchive
            }
            let input = Data(bytes[payload..<payload + entry.compressedSize])
            let result = entry.method == 8 ? ZlibData.inflate(input, size: entry.size, raw: true) : input
            guard let result, result.count == entry.size, ZlibData.crc(result) == entry.checksum else {
                throw ArchiveError.invalidArchive
            }
            return result
        }

        private func value(at start: Int, count: Int) throws -> Int {
            guard start >= 0, start + count <= bytes.count else { throw ArchiveError.invalidArchive }
            return bytes[start..<start + count].reversed().reduce(0) { ($0 << 8) | Int($1) }
        }
    }
}
