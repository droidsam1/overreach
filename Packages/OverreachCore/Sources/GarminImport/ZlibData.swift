import CZlib
import Foundation

enum ZlibData {
    static func compress(_ input: Data) -> Data? {
        let bound = compressBound(uLong(input.count))
        var output = Data(count: Int(bound))
        var size = bound
        let status = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                compress2(
                    destination.bindMemory(to: UInt8.self).baseAddress, &size,
                    source.bindMemory(to: UInt8.self).baseAddress, uLong(input.count), Z_DEFAULT_COMPRESSION
                )
            }
        }
        return status == Z_OK ? Data(output.prefix(Int(size))) : nil
    }

    static func inflate(_ input: Data, size: Int, raw: Bool = false) -> Data? {
        guard !input.isEmpty, size > 0 else { return nil }
        var stream = z_stream()
        guard inflateInit2_(&stream, raw ? -15 : 15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { inflateEnd(&stream) }
        var output = Data(count: size)
        let status = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: UInt8.self).baseAddress)
                stream.avail_in = UInt32(input.count)
                stream.next_out = destination.bindMemory(to: UInt8.self).baseAddress
                stream.avail_out = UInt32(size)
                return CZlib.inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END, stream.avail_in == 0, stream.total_out == size else { return nil }
        return output
    }

    static func crc(_ data: Data) -> UInt32 {
        data.withUnsafeBytes {
            UInt32(crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, UInt32(data.count)))
        }
    }
}
