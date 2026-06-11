import CryptoKit
import Foundation

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
