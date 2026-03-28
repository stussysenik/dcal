/* Infrastructure Layer -- Gamma ramp compression for BLOB storage.

   Gamma ramps are arrays of floating-point values (typically 256 or 1024
   entries per channel, 3 channels).  Storing them as raw Double arrays
   would waste space in SQLite.  This module provides lossless compression
   using zlib (available on all Apple platforms) and a simple binary format.

   Binary format:
     [UInt32 entryCount][Float32 x entryCount]
   This is then zlib-compressed before being stored as a BLOB.

   Learner note: We use Float32 instead of Float64 because gamma ramp
   values are inherently limited to the precision of the GPU LUT (8-10 bits),
   so 32-bit floats provide more than enough precision while halving the
   raw size before compression. */

import Foundation
import Compression

/// Compress an array of gamma ramp values into a compact BLOB for SQLite storage.
///
/// The values are first packed as little-endian Float32 with a UInt32 count header,
/// then compressed using the LZFSE algorithm (Apple's fast compressor).
///
/// - Parameter values: The gamma ramp values (e.g. 256 entries per channel, 768 total).
/// - Returns: Compressed data suitable for BLOB storage, or nil if compression fails.
public func compressRamp(_ values: [Double]) -> Data? {
    guard !values.isEmpty else { return nil }

    // Pack: [UInt32 count][Float32 x count]
    var count = UInt32(values.count)
    var raw = Data(bytes: &count, count: MemoryLayout<UInt32>.size)
    for value in values {
        var f = Float32(value)
        raw.append(Data(bytes: &f, count: MemoryLayout<Float32>.size))
    }

    // Compress using zlib (COMPRESSION_ZLIB is universally available).
    let sourceSize = raw.count
    let destinationSize = sourceSize + 512  // zlib may expand tiny inputs
    var destinationBuffer = Data(count: destinationSize)

    let compressedSize = destinationBuffer.withUnsafeMutableBytes { destPtr in
        raw.withUnsafeBytes { srcPtr in
            compression_encode_buffer(
                destPtr.bindMemory(to: UInt8.self).baseAddress!,
                destinationSize,
                srcPtr.bindMemory(to: UInt8.self).baseAddress!,
                sourceSize,
                nil,
                COMPRESSION_ZLIB
            )
        }
    }

    guard compressedSize > 0 else { return nil }
    return destinationBuffer.prefix(compressedSize)
}

/// Decompress a BLOB back into gamma ramp values.
///
/// - Parameter data: The compressed BLOB from SQLite.
/// - Returns: The original array of Double values, or nil if decompression fails.
public func decompressRamp(_ data: Data) -> [Double]? {
    guard !data.isEmpty else { return nil }

    // Decompress -- allocate a generous buffer (gamma ramps are small).
    let maxDecompressed = 1024 * 1024  // 1 MB is far more than any ramp
    var decompressedBuffer = Data(count: maxDecompressed)

    let decompressedSize = decompressedBuffer.withUnsafeMutableBytes { destPtr in
        data.withUnsafeBytes { srcPtr in
            compression_decode_buffer(
                destPtr.bindMemory(to: UInt8.self).baseAddress!,
                maxDecompressed,
                srcPtr.bindMemory(to: UInt8.self).baseAddress!,
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
    }

    guard decompressedSize > MemoryLayout<UInt32>.size else { return nil }

    let decompressed = decompressedBuffer.prefix(decompressedSize)

    // Read count header
    let count: UInt32 = decompressed.withUnsafeBytes { ptr in
        ptr.load(as: UInt32.self)
    }

    let expectedSize = MemoryLayout<UInt32>.size + Int(count) * MemoryLayout<Float32>.size
    guard decompressedSize == expectedSize else { return nil }

    // Read Float32 values
    var values: [Double] = []
    values.reserveCapacity(Int(count))

    decompressed.withUnsafeBytes { ptr in
        let floatPtr = (ptr.baseAddress! + MemoryLayout<UInt32>.size)
            .assumingMemoryBound(to: Float32.self)
        for i in 0..<Int(count) {
            values.append(Double(floatPtr[i]))
        }
    }

    return values
}
