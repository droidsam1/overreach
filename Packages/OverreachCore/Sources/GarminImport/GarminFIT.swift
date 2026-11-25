import Domain
import Foundation

/// The subset of Garmin FIT activity messages used by running performance.
public enum GarminFIT {
    public enum DecodeError: Error, Equatable, Sendable {
        case invalidHeader
        case invalidChecksum
        case unsupportedSize
        case malformedMessage
    }

    /// Reads a raw FIT file. The ZIP returned by the Garmin activity download is opened by the caller.
    public static func decode(_ data: Data) throws -> RunningTrack {
        // Bound the decoder's input independently of the size of the archive envelope.
        guard data.count <= 16 * 1024 * 1024 else { throw DecodeError.unsupportedSize }
        var reader = try Reader(data)
        return try reader.decode()
    }

    private static let epoch = Date(timeIntervalSince1970: 631_065_600)

    private struct Field {
        let number: UInt8
        let size: Int
        let type: UInt8
    }

    private struct Definition {
        let message: UInt32
        let littleEndian: Bool
        let fields: [Field]
        let developerBytes: Int
    }

    private struct Reader {
        private let bytes: [UInt8]
        private let limit: Int
        private var cursor: Int
        private var definitions: [UInt8: Definition] = [:]
        private var previousTimestamp: UInt32?
        private var samples: [RunningTrack.Sample] = []
        private var boundaries: [RunningTrack.Boundary] = []

        init(_ data: Data) throws {
            let bytes = Array(data)
            guard bytes.count >= 14, [12, 14].contains(bytes[0]), bytes[1] >> 4 <= 2,
                  bytes[8...11].elementsEqual(".FIT".utf8) else { throw DecodeError.invalidHeader }
            let headerSize = Int(bytes[0])
            let bodySize = Int(Self.integer(bytes[4..<8], littleEndian: true))
            let end = headerSize + bodySize
            guard end + 2 == bytes.count else { throw DecodeError.invalidHeader }
            let headerCRC = headerSize == 14 ? Self.integer(bytes[12..<14], littleEndian: true) : 0
            let fileCRC = Self.integer(bytes[end..<end + 2], littleEndian: true)
            guard headerCRC == 0 || headerCRC == Self.checksum(bytes.prefix(12)),
                  fileCRC == Self.checksum(bytes.prefix(end)) else { throw DecodeError.invalidChecksum }
            self.bytes = bytes
            cursor = headerSize
            limit = end
        }

        mutating func decode() throws -> RunningTrack {
            while cursor < limit {
                let header = try byte()
                if header & 0x80 != 0 {
                    try compressedMessage(header)
                } else if header & 0x40 != 0 {
                    try define(header)
                } else {
                    try message(local: header & 0x0F)
                }
            }
            // Device metadata alone does not prove which sensor supplied the recorded pulse.
            return RunningTrack(
                samples: samples.sorted { $0.date < $1.date },
                boundaries: boundaries.sorted { $0.date < $1.date }
            )
        }

        private mutating func define(_ header: UInt8) throws {
            _ = try byte()
            let architecture = try byte()
            guard architecture <= 1 else { throw DecodeError.malformedMessage }
            let littleEndian = architecture == 0
            let global = Self.integer(try read(2), littleEndian: littleEndian)
            let count = Int(try byte())
            let fields = try (0..<count).map { _ in
                Field(number: try byte(), size: Int(try byte()), type: try byte() & 0x1F)
            }
            var developerBytes = 0
            if header & 0x20 != 0 {
                let developerFields = Int(try byte())
                for _ in 0..<developerFields {
                    _ = try byte()
                    developerBytes += Int(try byte())
                    _ = try byte()
                }
            }
            definitions[header & 0x0F] = Definition(
                message: global, littleEndian: littleEndian, fields: fields, developerBytes: developerBytes
            )
        }

        private mutating func compressedMessage(_ header: UInt8) throws {
            guard let previousTimestamp else { throw DecodeError.malformedMessage }
            let offset = UInt32(header & 0x1F)
            let previousOffset = previousTimestamp & 0x1F
            let delta = (offset + 32 - previousOffset) & 0x1F
            let (timestamp, overflow) = previousTimestamp.addingReportingOverflow(delta)
            guard !overflow, timestamp != UInt32.max else { throw DecodeError.malformedMessage }
            try message(local: (header >> 5) & 0x03, timestamp: timestamp)
        }

        private mutating func message(local: UInt8, timestamp: UInt32? = nil) throws {
            guard let definition = definitions[local] else { throw DecodeError.malformedMessage }
            var fields = definition.fields[...]
            var values: [UInt8: UInt32] = [:]
            if let timestamp {
                guard let first = fields.first, first.number == 253, first.size == 4, first.type == 6 else {
                    throw DecodeError.malformedMessage
                }
                fields = fields.dropFirst()
                values[253] = timestamp
            }
            for field in fields {
                let raw = try read(field.size)
                if field.number == 253 || [19, 20, 21].contains(definition.message) {
                    values[field.number] = Self.value(raw, type: field.type, littleEndian: definition.littleEndian)
                }
            }
            _ = try read(definition.developerBytes)
            guard let timestamp = values[253] else { return }
            previousTimestamp = timestamp
            let date = GarminFIT.epoch.addingTimeInterval(Double(timestamp))
            if definition.message == 20 {
                samples.append(Self.sample(date: date, values: values))
            } else if let kind = Self.boundaryKind(for: definition.message, values: values) {
                boundaries.append(.init(date: date, kind: kind))
            }
        }

        private static func boundaryKind(
            for message: UInt32, values: [UInt8: UInt32]
        ) -> RunningTrack.BoundaryKind? {
            if message == 19, let trigger = values[24] {
                if trigger == 0 { return .manualLap }
                if (1...6).contains(trigger) || trigger == 8 { return .automaticLap }
            }
            if message == 21, values[0] == 0, let event = values[1] {
                if event == 0 { return .timerStart }
                if [1, 4, 8, 9].contains(event) { return .timerStop }
            }
            return nil
        }

        private static func sample(date: Date, values: [UInt8: UInt32]) -> RunningTrack.Sample {
            let cadence = values[4].map { (Double($0) + Double(values[53] ?? 0) / 128) * 2 }
            let semicircles = 180.0 / 2_147_483_648
            return RunningTrack.Sample(
                date: date,
                distanceMeters: values[5].map { Double($0) / 100 },
                speedMetersPerSecond: (values[73] ?? values[6]).map { Double($0) / 1_000 },
                altitudeMeters: (values[78] ?? values[2]).map { Double($0) / 5 - 500 },
                heartRateBPM: values[3].map(Double.init),
                cadenceStepsPerMinute: cadence,
                latitude: values[0].map { Double(Int32(bitPattern: $0)) * semicircles },
                longitude: values[1].map { Double(Int32(bitPattern: $0)) * semicircles }
            )
        }

        private static func value(_ bytes: ArraySlice<UInt8>, type: UInt8, littleEndian: Bool) -> UInt32? {
            let expectedSize: Int
            let invalid: UInt32
            switch type {
            case 0, 2: (expectedSize, invalid) = (1, 0xFF)
            case 4: (expectedSize, invalid) = (2, 0xFFFF)
            case 5: (expectedSize, invalid) = (4, 0x7FFF_FFFF)
            case 6: (expectedSize, invalid) = (4, 0xFFFF_FFFF)
            default: return nil
            }
            guard bytes.count == expectedSize else { return nil }
            let number = integer(bytes, littleEndian: littleEndian)
            return number == invalid ? nil : number
        }

        private static func integer(_ bytes: ArraySlice<UInt8>, littleEndian: Bool) -> UInt32 {
            let ordered = littleEndian ? Array(bytes.reversed()) : Array(bytes)
            return ordered.reduce(0) { ($0 << 8) | UInt32($1) }
        }

        private static func checksum(_ bytes: ArraySlice<UInt8>) -> UInt32 {
            var crc: UInt32 = 0
            for byte in bytes {
                crc ^= UInt32(byte)
                for _ in 0..<8 {
                    crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0xA001
                }
            }
            return crc
        }

        private mutating func read(_ count: Int) throws -> ArraySlice<UInt8> {
            guard count <= limit - cursor else { throw DecodeError.malformedMessage }
            let start = cursor
            cursor += count
            return bytes[start..<cursor]
        }

        private mutating func byte() throws -> UInt8 {
            guard let first = try read(1).first else { throw DecodeError.malformedMessage }
            return first
        }
    }
}
