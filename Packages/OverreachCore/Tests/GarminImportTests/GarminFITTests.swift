import Foundation
import GarminImport
import Testing

struct GarminFITTests {
    @Test func recordsAndLapBoundariesUseFITUnits() throws {
        let fields: [UInt8] = [
            253, 4, 0x86, 0, 4, 0x85, 1, 4, 0x85, 3, 1, 2, 4, 1, 2,
            53, 1, 2, 5, 4, 0x86, 6, 2, 0x84, 78, 4, 0x86
        ]
        let records = [0x40, 0, 0, 20, 0, 9] + fields
        let sample: [UInt8] = [
            0, 31, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 192, 148, 83, 64,
            0x10, 0x27, 0, 0, 0x50, 0x0C, 0x26, 0x0B, 0, 0
        ]
        let compressed: [UInt8] = [0x81] + Array(sample.dropFirst(5))
        let lapDefinition: [UInt8] = [0x41, 0, 1, 0, 19, 2, 253, 4, 0x86, 24, 1, 0]
        let laps: [UInt8] = [1, 0, 0, 0, 35, 0, 1, 0, 0, 0, 40, 2]
        let eventDefinition: [UInt8] = [0x42, 0, 0, 21, 0, 3, 253, 4, 0x86, 0, 1, 0, 1, 1, 0]
        let events: [UInt8] = [2, 31, 0, 0, 0, 0, 0, 2, 45, 0, 0, 0, 0, 4]

        let track = try GarminFIT.decode(fit(records + sample + compressed + lapDefinition + laps
                                             + eventDefinition + events))
        #expect(track.samples.count == 2)
        let result = try #require(track.samples.first)
        #expect(result.date.timeIntervalSince1970 == 631_065_631)
        #expect(track.samples.last?.date.timeIntervalSince(result.date) == 2)
        #expect(result.heartRateBPM == 148)
        #expect(result.cadenceStepsPerMinute == 167)
        #expect(result.distanceMeters == 100)
        #expect(result.speedMetersPerSecond == 3.152)
        let altitude = try #require(result.altitudeMeters)
        #expect(abs(altitude - 70.8) < 0.001)
        #expect(result.latitude == 90)
        #expect(result.longitude == -90)
        #expect(track.boundaries.map(\.kind) == [.timerStart, .manualLap, .automaticLap, .timerStop])
        #expect(track.heartRateSensorID == nil)
    }

    @Test func developerFieldsAreSkippedAndMissingMeasurementsStayMissing() throws {
        let data: [UInt8] = [
            0x60, 0, 0, 20, 0, 2, 253, 4, 0x86, 3, 1, 2, 1, 0, 2, 0,
            0, 5, 0, 0, 0, 0xFF, 91, 7,
            0, 6, 0, 0, 0, 145, 50, 4
        ]
        let track = try GarminFIT.decode(fit(data))
        #expect(track.samples.map(\.heartRateBPM) == [nil, 145])
        #expect(track.samples.allSatisfy { $0.distanceMeters == nil })
    }

    @Test func rejectsCorruptPayloadAndMissingDefinition() throws {
        var corrupt = fit([0])
        corrupt[corrupt.count - 1] ^= 1
        #expect(throws: GarminFIT.DecodeError.invalidChecksum) { try GarminFIT.decode(corrupt) }
        #expect(throws: GarminFIT.DecodeError.malformedMessage) { try GarminFIT.decode(fit([0])) }
        #expect(throws: GarminFIT.DecodeError.invalidHeader) { try GarminFIT.decode(Data()) }
    }

    private func fit(_ body: [UInt8]) -> Data {
        var header: [UInt8] = [12, 0x20, 0, 0]
        for offset in 0..<4 {
            header.append(UInt8(truncatingIfNeeded: body.count >> (8 * offset)))
        }
        header += [0x2E, 0x46, 0x49, 0x54]
        let bytes = header + body
        let polynomial: UInt16 = 0xA001
        let crc = bytes.reduce(UInt16.zero) { result, byte in
            (0..<8).reduce(result ^ UInt16(byte)) { value, _ in
                (value >> 1) ^ (value & 1 == 0 ? 0 : polynomial)
            }
        }
        return Data(bytes + [UInt8(truncatingIfNeeded: crc), UInt8(crc >> 8)])
    }
}
