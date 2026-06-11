import AVFoundation
import CoreGraphics
import CryptoKit
import Foundation

struct PeakPoint: Equatable {
    let min: Float32
    let max: Float32
    let rms: Float32
}

struct PeakformLevel: Equatable {
    let samplesPerPeak: Int
    let peaks: [PeakPoint]
}

struct PeakformData: Equatable {
    static let defaultSamplesPerPeakLevels = [128, 256, 512, 1_024, 2_048, 4_096]

    let duration: TimeInterval
    let sampleRate: Double
    let levels: [PeakformLevel]

    var samplesPerPeak: Int {
        defaultLevel?.samplesPerPeak ?? levels.first?.samplesPerPeak ?? 0
    }

    var peaks: [PeakPoint] {
        defaultLevel?.peaks ?? levels.first?.peaks ?? []
    }

    func level(samplesPerPeak: Int) -> PeakformLevel? {
        levels.first { $0.samplesPerPeak == samplesPerPeak }
    }

    func preferredLevel(for viewport: TimelineViewport, width: CGFloat) -> PeakformLevel? {
        guard
            sampleRate > 0,
            viewport.visibleDuration > 0,
            width > 0,
            !levels.isEmpty
        else {
            return defaultLevel ?? levels.first
        }

        let visibleSamples = sampleRate * viewport.visibleDuration
        let targetPeakCount = max(Double(width) / 1.5, 1)
        let targetSamplesPerPeak = max(1, visibleSamples / targetPeakCount)

        return levels.min { lhs, rhs in
            abs(Double(lhs.samplesPerPeak) - targetSamplesPerPeak) < abs(Double(rhs.samplesPerPeak) - targetSamplesPerPeak)
        }
    }

    private var defaultLevel: PeakformLevel? {
        level(samplesPerPeak: 512)
    }
}

protocol PeakformProvider {
    var samplesPerPeakLevels: [Int] { get }
    func peakform(for url: URL) async throws -> PeakformData
    func removeCachedPeakform(for url: URL) async
}

extension PeakformProvider {
    func removeCachedPeakform(for url: URL) async {}
}

enum PeakformProviderError: LocalizedError, Equatable {
    case unsupportedBuffer
    case emptyAudio
    case invalidCache
    case unsupportedCacheVersion

    var errorDescription: String? {
        switch self {
        case .unsupportedBuffer:
            return "Could not decode this file into peakform data."
        case .emptyAudio:
            return "The audio file did not contain enough signal to draw a peakform."
        case .invalidCache:
            return "The peakform cache is invalid."
        case .unsupportedCacheVersion:
            return "The peakform cache version is not supported."
        }
    }
}

final class CachedPeakformProvider: PeakformProvider {
    let samplesPerPeakLevels: [Int]

    private let cache = PeakformBinaryCache()
    private let fileManager: FileManager
    private let generator: PeakformGenerator

    init(
        samplesPerPeakLevels: [Int] = PeakformData.defaultSamplesPerPeakLevels,
        fileManager: FileManager = .default
    ) {
        self.samplesPerPeakLevels = samplesPerPeakLevels
        self.fileManager = fileManager
        self.generator = PeakformGenerator(samplesPerPeakLevels: samplesPerPeakLevels)
    }

    func peakform(for url: URL) async throws -> PeakformData {
        try await Task.detached(priority: .userInitiated) {
            let cacheURL = try self.cacheURL(for: url)

            if self.fileManager.fileExists(atPath: cacheURL.path) {
                do {
                    return try self.cache.read(from: cacheURL)
                } catch {
                    try? self.fileManager.removeItem(at: cacheURL)
                }
            }

            let peakform = try self.generator.buildPeakform(from: url)
            try? self.cache.write(peakform, to: cacheURL)
            return peakform
        }.value
    }

    func removeCachedPeakform(for url: URL) async {
        await Task.detached(priority: .utility) {
            guard let cacheURL = try? self.cacheURL(for: url) else { return }
            try? self.fileManager.removeItem(at: cacheURL)
        }.value
    }

    private func cacheURL(for audioURL: URL) throws -> URL {
        let hash = try audioFileHash(for: audioURL)
        let directory = applicationSupportDirectory()
            .appendingPathComponent("PeakformCache", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
            .appendingPathComponent("\(hash).peakform", isDirectory: false)
    }

    private func applicationSupportDirectory() -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseURL.appendingPathComponent("JammLab", isDirectory: true)
    }

    private func audioFileHash(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()

        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 1_048_576)
            guard !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

struct PeakformGenerator {
    let samplesPerPeakLevels: [Int]

    init(samplesPerPeakLevels: [Int] = PeakformData.defaultSamplesPerPeakLevels) {
        self.samplesPerPeakLevels = samplesPerPeakLevels
            .filter { $0 > 0 }
            .uniqued()
            .sorted()
    }

    func buildPeakform(from url: URL) throws -> PeakformData {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat

        guard file.length > 0 else {
            throw PeakformProviderError.emptyAudio
        }

        let frameCapacity: AVAudioFrameCount = 16_384
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            throw PeakformProviderError.unsupportedBuffer
        }

        let channelCount = Int(format.channelCount)
        var accumulators = samplesPerPeakLevels.map { samplesPerPeak in
            PeakformLevelAccumulator(
                samplesPerPeak: samplesPerPeak,
                estimatedFrameCount: Int(file.length)
            )
        }
        var hasSignal = false

        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: frameCapacity)
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { break }
            guard let channels = buffer.floatChannelData else {
                throw PeakformProviderError.unsupportedBuffer
            }

            for frame in 0..<frameLength {
                var mono = Float32(0)

                for channel in 0..<channelCount {
                    mono += channels[channel][frame] / Float32(channelCount)
                }

                if abs(mono) > 0.0001 {
                    hasSignal = true
                }

                for index in accumulators.indices {
                    accumulators[index].append(mono)
                }
            }
        }

        for index in accumulators.indices {
            accumulators[index].finish()
        }

        let levels = accumulators.map(\.level).filter { !$0.peaks.isEmpty }
        guard hasSignal, !levels.isEmpty else {
            throw PeakformProviderError.emptyAudio
        }

        return PeakformData(
            duration: Double(file.length) / format.sampleRate,
            sampleRate: format.sampleRate,
            levels: levels
        )
    }
}

private struct PeakformLevelAccumulator {
    let samplesPerPeak: Int
    private(set) var peaks: [PeakPoint] = []
    private var blockMin = Float32.greatestFiniteMagnitude
    private var blockMax = -Float32.greatestFiniteMagnitude
    private var blockSquareSum: Double = 0
    private var blockSampleCount = 0

    init(samplesPerPeak: Int, estimatedFrameCount: Int) {
        self.samplesPerPeak = samplesPerPeak
        peaks.reserveCapacity(max(1, estimatedFrameCount / samplesPerPeak))
    }

    mutating func append(_ sample: Float32) {
        blockMin = min(blockMin, sample)
        blockMax = max(blockMax, sample)
        blockSquareSum += Double(sample * sample)
        blockSampleCount += 1

        appendPeakIfNeeded()
    }

    mutating func finish() {
        appendPeakIfNeeded(force: true)
    }

    var level: PeakformLevel {
        PeakformLevel(samplesPerPeak: samplesPerPeak, peaks: peaks)
    }

    private mutating func appendPeakIfNeeded(force: Bool = false) {
        guard blockSampleCount == samplesPerPeak || (force && blockSampleCount > 0) else { return }

        let rms = Float32(sqrt(blockSquareSum / Double(blockSampleCount)))
        peaks.append(PeakPoint(min: blockMin, max: blockMax, rms: rms))

        blockMin = Float32.greatestFiniteMagnitude
        blockMax = -Float32.greatestFiniteMagnitude
        blockSquareSum = 0
        blockSampleCount = 0
    }
}

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

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
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
