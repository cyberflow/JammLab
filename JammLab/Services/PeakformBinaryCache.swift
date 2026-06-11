import Foundation

struct PeakformBinaryCache {
    private let magic: UInt32 = 0x5045_414B
    private let version: UInt16 = 2
    private let channelModeMono: UInt8 = 1
    private let headerByteCount = 64
    private let levelDirectoryEntryByteCount = 24
    private let peakByteCount = 12

    func read(from url: URL) throws -> PeakformData {
        let data = try Data(contentsOf: url)
        guard data.count >= headerByteCount else {
            throw PeakformProviderError.invalidCache
        }

        var reader = BinaryReader(data: data)
        let storedMagic = try reader.readUInt32()
        guard storedMagic == magic else {
            throw PeakformProviderError.invalidCache
        }

        let storedVersion = try reader.readUInt16()
        guard storedVersion == version else {
            throw PeakformProviderError.unsupportedCacheVersion
        }

        _ = try reader.readUInt16()
        let sampleRate = try reader.readDouble()
        let duration = try reader.readDouble()
        let levelCount = Int(try reader.readUInt32())
        let channelMode = try reader.readUInt8()

        guard
            sampleRate > 0,
            duration > 0,
            levelCount > 0,
            channelMode == channelModeMono
        else {
            throw PeakformProviderError.invalidCache
        }

        let directoryStart = headerByteCount
        let directoryByteCount = levelCount * levelDirectoryEntryByteCount
        guard data.count >= directoryStart + directoryByteCount else {
            throw PeakformProviderError.invalidCache
        }

        reader.seek(to: directoryStart)
        var entries: [PeakformLevelDirectoryEntry] = []
        entries.reserveCapacity(levelCount)

        for _ in 0..<levelCount {
            let samplesPerPeak = Int(try reader.readUInt32())
            _ = try reader.readUInt32()
            let peakCount = Int(try reader.readUInt64())
            let dataOffset = Int(try reader.readUInt64())

            guard
                samplesPerPeak > 0,
                peakCount > 0,
                dataOffset >= directoryStart + directoryByteCount,
                dataOffset <= data.count
            else {
                throw PeakformProviderError.invalidCache
            }

            entries.append(PeakformLevelDirectoryEntry(
                samplesPerPeak: samplesPerPeak,
                peakCount: peakCount,
                dataOffset: dataOffset
            ))
        }

        var levels: [PeakformLevel] = []
        levels.reserveCapacity(levelCount)
        var expectedEndOffset = directoryStart + directoryByteCount

        for entry in entries {
            let byteCount = entry.peakCount * peakByteCount
            guard entry.dataOffset == expectedEndOffset, entry.dataOffset + byteCount <= data.count else {
                throw PeakformProviderError.invalidCache
            }

            reader.seek(to: entry.dataOffset)
            var peaks: [PeakPoint] = []
            peaks.reserveCapacity(entry.peakCount)

            for _ in 0..<entry.peakCount {
                peaks.append(PeakPoint(
                    min: try reader.readFloat32(),
                    max: try reader.readFloat32(),
                    rms: try reader.readFloat32()
                ))
            }

            levels.append(PeakformLevel(samplesPerPeak: entry.samplesPerPeak, peaks: peaks))
            expectedEndOffset += byteCount
        }

        guard expectedEndOffset == data.count else {
            throw PeakformProviderError.invalidCache
        }

        return PeakformData(
            duration: duration,
            sampleRate: sampleRate,
            levels: levels.sorted { $0.samplesPerPeak < $1.samplesPerPeak }
        )
    }

    func write(_ peakform: PeakformData, to url: URL) throws {
        let levels = peakform.levels
            .filter { $0.samplesPerPeak > 0 && !$0.peaks.isEmpty }
            .sorted { $0.samplesPerPeak < $1.samplesPerPeak }

        guard peakform.sampleRate > 0, peakform.duration > 0, !levels.isEmpty else {
            throw PeakformProviderError.invalidCache
        }

        let directoryByteCount = levels.count * levelDirectoryEntryByteCount
        let peakDataByteCount = levels.reduce(0) { $0 + $1.peaks.count * peakByteCount }

        var data = Data()
        data.reserveCapacity(headerByteCount + directoryByteCount + peakDataByteCount)

        data.appendUInt32(magic)
        data.appendUInt16(version)
        data.appendUInt16(0)
        data.appendDouble(peakform.sampleRate)
        data.appendDouble(peakform.duration)
        data.appendUInt32(UInt32(levels.count))
        data.appendUInt8(channelModeMono)

        if data.count < headerByteCount {
            data.append(contentsOf: repeatElement(UInt8(0), count: headerByteCount - data.count))
        }

        var dataOffset = headerByteCount + directoryByteCount
        for level in levels {
            data.appendUInt32(UInt32(level.samplesPerPeak))
            data.appendUInt32(0)
            data.appendUInt64(UInt64(level.peaks.count))
            data.appendUInt64(UInt64(dataOffset))
            dataOffset += level.peaks.count * peakByteCount
        }

        for level in levels {
            for peak in level.peaks {
                data.appendFloat32(peak.min)
                data.appendFloat32(peak.max)
                data.appendFloat32(peak.rms)
            }
        }

        try data.write(to: url, options: [.atomic])
    }
}

private struct PeakformLevelDirectoryEntry {
    let samplesPerPeak: Int
    let peakCount: Int
    let dataOffset: Int
}

private struct BinaryReader {
    let data: Data
    private(set) var offset = 0

    mutating func seek(to offset: Int) {
        self.offset = offset
    }

    mutating func readUInt8() throws -> UInt8 {
        guard offset + 1 <= data.count else { throw PeakformProviderError.invalidCache }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readUInt16() throws -> UInt16 {
        UInt16(littleEndian: try readInteger())
    }

    mutating func readUInt32() throws -> UInt32 {
        UInt32(littleEndian: try readInteger())
    }

    mutating func readUInt64() throws -> UInt64 {
        UInt64(littleEndian: try readInteger())
    }

    mutating func readFloat32() throws -> Float32 {
        Float32(bitPattern: try readUInt32())
    }

    mutating func readDouble() throws -> Double {
        Double(bitPattern: try readUInt64())
    }

    private mutating func readInteger<T: FixedWidthInteger>() throws -> T {
        let byteCount = MemoryLayout<T>.size
        guard offset + byteCount <= data.count else {
            throw PeakformProviderError.invalidCache
        }

        var value: T = 0
        for index in 0..<byteCount {
            value |= T(data[offset + index]) << T(index * 8)
        }

        offset += byteCount
        return value
    }
}

private extension Data {
    mutating func appendUInt8(_ value: UInt8) {
        append(value)
    }

    mutating func appendUInt16(_ value: UInt16) {
        appendInteger(value.littleEndian)
    }

    mutating func appendUInt32(_ value: UInt32) {
        appendInteger(value.littleEndian)
    }

    mutating func appendUInt64(_ value: UInt64) {
        appendInteger(value.littleEndian)
    }

    mutating func appendFloat32(_ value: Float32) {
        appendUInt32(value.bitPattern)
    }

    mutating func appendDouble(_ value: Double) {
        appendUInt64(value.bitPattern)
    }

    private mutating func appendInteger<T: FixedWidthInteger>(_ value: T) {
        var value = value
        Swift.withUnsafeBytes(of: &value) { buffer in
            append(contentsOf: buffer)
        }
    }
}
