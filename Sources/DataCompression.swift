import Foundation
import Compression

enum DataCompression {
    static func compress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        let capacity = max(64, data.count + data.count / 8 + 64)
        var destination = [UInt8](repeating: 0, count: capacity)
        let written = data.withUnsafeBytes { source in
            compression_encode_buffer(&destination, capacity, source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_LZMA)
        }
        guard written > 0 else { throw DataPortError.exportFailed("LZMA compression failed") }
        return Data(destination.prefix(written))
    }

    static func decompress(_ data: Data, expectedSize: Int) throws -> Data {
        guard expectedSize >= 0 else { throw DataPortError.importFailed("Invalid uncompressed size") }
        guard expectedSize > 0 else { return Data() }
        var destination = [UInt8](repeating: 0, count: expectedSize)
        let written = data.withUnsafeBytes { source in
            compression_decode_buffer(&destination, expectedSize, source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_LZMA)
        }
        guard written == expectedSize else { throw DataPortError.importFailed("LZMA decompression size mismatch") }
        return Data(destination)
    }

    static func compressedSize(of data: Data) -> Int {
        (try? compress(data))?.count ?? data.count
    }
}