import AVFoundation
import CryptoKit
import Foundation

enum StemSeparationError: LocalizedError {
    case missingAudioFile
    case helperNotRunning(String)
    case helperJobFailed(String)
    case helperJobTimedOut(String)
    case incompleteOutput([StemType])
    case invalidStemDuration(StemType)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingAudioFile:
            return "Import an audio file before separating stems."
        case .helperNotRunning:
            return "Stem helper could not be started automatically. Check that JammLabStemHelper is bundled with the app, then retry separation."
        case .helperJobFailed(let details):
            return "Stem separation failed. \(details)"
        case .helperJobTimedOut:
            return "Stem helper did not finish the job in time."
        case .incompleteOutput(let missingTypes):
            let names = missingTypes.map(\.title).joined(separator: ", ")
            return "Stem helper finished, but these stems are missing: \(names)."
        case .invalidStemDuration(let type):
            return "\(type.title) stem duration does not match the original track."
        case .cancelled:
            return "Stem separation was cancelled."
        }
    }

    var diagnostics: String {
        switch self {
        case .missingAudioFile, .cancelled:
            return localizedDescription
        case .helperNotRunning(let details):
            return "Stem helper is not running\n\(details)"
        case .helperJobFailed(let details):
            return "Stem helper job failed\n\(details)"
        case .helperJobTimedOut(let details):
            return "Stem helper job timed out\n\(details)"
        case .incompleteOutput(let missingTypes):
            return "Incomplete helper output. Missing stems: \(missingTypes.map(\.rawValue).joined(separator: ", "))"
        case .invalidStemDuration(let type):
            return "Invalid stem duration for \(type.rawValue)"
        }
    }
}

struct StemSeparationProgress {
    var phase: StemSeparationPhase
    var progress: Double?
    var status: String
}

enum StemJobInputMode: Equatable {
    case direct
    case staged
}

struct StemJobInput: Equatable {
    var audioPath: String
    var stagedInputDirectory: URL?
}

final class StemSeparationService {
    static let settingsVersion = 2

    private let fileManager: FileManager
    private let helperProcessController: StemHelperProcessController
    private let appSettingsStore: AppSettingsStore
    private let isSandboxed: () -> Bool
    private let applicationSupportDirectoryOverride: URL?
    private let pollInterval: UInt64 = 500_000_000
    private var activeJobDirectory: URL?

    init(
        fileManager: FileManager = .default,
        appSettingsStore: AppSettingsStore = AppSettingsStore(),
        helperProcessController: StemHelperProcessController? = nil,
        isSandboxed: @escaping () -> Bool = StemSeparationService.defaultSandboxDetection,
        applicationSupportDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.appSettingsStore = appSettingsStore
        self.isSandboxed = isSandboxed
        self.applicationSupportDirectoryOverride = applicationSupportDirectory
        self.helperProcessController = helperProcessController ?? StemHelperProcessController(
            heartbeatURL: StemJobFiles
                .currentJobsDirectory(in: applicationSupportDirectory ?? Self.applicationSupportDirectory(fileManager: fileManager))
                .appendingPathComponent(StemJobFiles.heartbeatFilename),
            fileManager: fileManager
        )
    }

    func cachedResult(for audioURL: URL, method: StemSeparationMethod = .defaultValue) throws -> StemCacheMetadata? {
        let fingerprint = try sourceFingerprint(for: audioURL)
        let cacheKey = cacheKey(for: fingerprint, method: method)
        if let metadata = try validatedMetadata(in: cacheDirectory(for: cacheKey), expectedFingerprint: fingerprint, method: method) {
            return metadata
        }

        return try discoverCachedMetadata(matching: fingerprint, method: method)
    }

    func cachedResult(cacheKey: String, expectedFingerprint: StemSourceFingerprint) throws -> StemCacheMetadata? {
        try validatedMetadata(
            in: cacheDirectory(for: cacheKey),
            expectedFingerprint: expectedFingerprint,
            allowsPathMismatch: true
        )
    }

    func removeCachedResult(cacheKey: String) {
        try? fileManager.removeItem(at: cacheDirectory(for: cacheKey))
    }

    func sourceFingerprint(for audioURL: URL) throws -> StemSourceFingerprint {
        let values = try audioURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return StemSourceFingerprint(
            path: audioURL.path,
            fileSize: Int64(values.fileSize ?? 0),
            modificationTime: values.contentModificationDate?.timeIntervalSince1970 ?? 0
        )
    }

    func separate(
        audioURL: URL,
        originalDuration: TimeInterval,
        method: StemSeparationMethod = .defaultValue,
        progress: @escaping @Sendable (StemSeparationProgress) -> Void
    ) async throws -> StemCacheMetadata {
        let fingerprint = try sourceFingerprint(for: audioURL)
        let cacheKey = cacheKey(for: fingerprint, method: method)
        let cacheDirectory = cacheDirectory(for: cacheKey)

        if let cached = try validatedMetadata(in: cacheDirectory, expectedFingerprint: fingerprint, method: method) {
            progress(StemSeparationProgress(phase: .completed, progress: 1, status: "Using cached stems"))
            return cached
        }

        let jobDirectory = jobsDirectory().appendingPathComponent(UUID().uuidString, isDirectory: true)

        progress(StemSeparationProgress(phase: .checkingBackend, progress: nil, status: "Waiting for helper"))
        do {
            try await helperProcessController.ensureRunning()
        } catch let error as StemHelperLaunchError {
            throw StemSeparationError.helperNotRunning(error.diagnostics)
        } catch {
            throw StemSeparationError.helperNotRunning(error.localizedDescription)
        }

        let initialInputMode = isSandboxed() ? StemJobInputMode.staged : .direct

        let result: StemCacheMetadata
        do {
            result = try await runJob(
                audioURL: audioURL,
                fingerprint: fingerprint,
                cacheKey: cacheKey,
                cacheDirectory: cacheDirectory,
                jobDirectory: jobDirectory,
                inputMode: initialInputMode,
                method: method,
                originalDuration: originalDuration,
                progress: progress
            )
        } catch {
            guard initialInputMode == .direct,
                  isInputPermissionFailure(error, originalAudioPath: audioURL.path)
            else {
                throw error
            }

            let retryJobDirectory = jobsDirectory().appendingPathComponent(UUID().uuidString, isDirectory: true)
            progress(StemSeparationProgress(phase: .checkingBackend, progress: nil, status: "Retrying with sandbox input copy"))
            result = try await runJob(
                audioURL: audioURL,
                fingerprint: fingerprint,
                cacheKey: cacheKey,
                cacheDirectory: cacheDirectory,
                jobDirectory: retryJobDirectory,
                inputMode: .staged,
                method: method,
                originalDuration: originalDuration,
                progress: progress
            )
        }

        progress(StemSeparationProgress(phase: .completed, progress: 1, status: "Stems ready"))
        return result
    }

    func cancel() {
        guard let activeJobDirectory else { return }
        let cancelURL = activeJobDirectory.appendingPathComponent(StemJobFiles.cancelFilename)
        try? Data("cancelled".utf8).write(to: cancelURL, options: .atomic)
    }

    private func runJob(
        audioURL: URL,
        fingerprint: StemSourceFingerprint,
        cacheKey: String,
        cacheDirectory: URL,
        jobDirectory: URL,
        inputMode: StemJobInputMode,
        method: StemSeparationMethod,
        originalDuration: TimeInterval,
        progress: @escaping @Sendable (StemSeparationProgress) -> Void
    ) async throws -> StemCacheMetadata {
        activeJobDirectory = jobDirectory
        let stagedInputDirectory = try createJob(
            audioURL: audioURL,
            fingerprint: fingerprint,
            cacheKey: cacheKey,
            cacheDirectory: cacheDirectory,
            jobDirectory: jobDirectory,
            inputMode: inputMode,
            method: method
        )

        defer { activeJobDirectory = nil }
        let result = try await waitForJob(
            jobDirectory: jobDirectory,
            originalDuration: originalDuration,
            progress: progress
        )
        if let stagedInputDirectory {
            try? fileManager.removeItem(at: stagedInputDirectory)
        }
        return result
    }

    @discardableResult
    func createJobForTesting(
        audioURL: URL,
        fingerprint: StemSourceFingerprint,
        cacheKey: String,
        cacheDirectory: URL,
        jobDirectory: URL,
        inputMode: StemJobInputMode,
        method: StemSeparationMethod = .defaultValue
    ) throws -> URL? {
        try createJob(
            audioURL: audioURL,
            fingerprint: fingerprint,
            cacheKey: cacheKey,
            cacheDirectory: cacheDirectory,
            jobDirectory: jobDirectory,
            inputMode: inputMode,
            method: method
        )
    }

    private func createJob(
        audioURL: URL,
        fingerprint: StemSourceFingerprint,
        cacheKey: String,
        cacheDirectory: URL,
        jobDirectory: URL,
        inputMode: StemJobInputMode,
        method: StemSeparationMethod
    ) throws -> URL? {
        try fileManager.createDirectory(at: jobDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: modelDirectory(), withIntermediateDirectories: true)
        let input = try jobInput(for: audioURL, jobDirectory: jobDirectory, mode: inputMode)

        let request = StemJobRequest(
            jobID: jobDirectory.lastPathComponent,
            audioPath: input.audioPath,
            cacheKey: cacheKey,
            cacheDirectoryPath: cacheDirectory.path,
            modelDirectoryPath: modelDirectory().path,
            sourceFingerprint: fingerprint,
            separationMethodID: method.id,
            expectedStemTypes: method.stemTypes,
            modelName: method.modelName,
            settingsVersion: Self.settingsVersion,
            audioSeparatorPath: nil,
            audioSeparatorBookmarkData: nil,
            computeMode: appSettingsStore.stemBackendComputeMode.helperArgument,
            createdAt: Date()
        )
        try writeJSON(request, to: jobDirectory.appendingPathComponent(StemJobFiles.requestFilename))
        try writeJSON(
            StemJobStatus.pending(jobID: request.jobID),
            to: jobDirectory.appendingPathComponent(StemJobFiles.statusFilename)
        )
        return input.stagedInputDirectory
    }

    private func waitForJob(
        jobDirectory: URL,
        originalDuration: TimeInterval,
        progress: @escaping @Sendable (StemSeparationProgress) -> Void
    ) async throws -> StemCacheMetadata {
        var helperWasSeen = readHeartbeat()?.isFresh == true
        let startedAt = Date()
        var lastDiagnostics = "job: \(jobDirectory.path)"

        while !Task.isCancelled {
            if fileManager.fileExists(atPath: jobDirectory.appendingPathComponent(StemJobFiles.cancelFilename).path) {
                throw StemSeparationError.cancelled
            }

            if let heartbeat = readHeartbeat(), heartbeat.isFresh {
                helperWasSeen = true
            } else if !helperWasSeen, Date().timeIntervalSince(startedAt) > 3 {
                throw StemSeparationError.helperNotRunning(lastDiagnostics)
            }

            if let status: StemJobStatus = try? readJSON(from: jobDirectory.appendingPathComponent(StemJobFiles.statusFilename)) {
                lastDiagnostics = diagnostics(for: jobDirectory, status: status)
                progress(
                    StemSeparationProgress(
                        phase: status.phase.viewPhase,
                        progress: status.progress,
                        status: status.message
                    )
                )

                switch status.phase {
                case .completed:
                    let result: StemJobResult = try readJSON(from: jobDirectory.appendingPathComponent(StemJobFiles.resultFilename))
                    try await validate(stems: result.metadata.stems, originalDuration: originalDuration)
                    return result.metadata
                case .failed:
                    throw StemSeparationError.helperJobFailed(lastDiagnostics)
                case .cancelled:
                    throw StemSeparationError.cancelled
                case .pending, .checkingBackend, .processing:
                    break
                }
            }

            if Date().timeIntervalSince(startedAt) > 60 * 60 * 3 {
                throw StemSeparationError.helperJobTimedOut(lastDiagnostics)
            }

            try await Task.sleep(nanoseconds: pollInterval)
        }

        throw StemSeparationError.cancelled
    }

    private func readHeartbeat() -> StemHelperHeartbeat? {
        try? readJSON(from: jobsDirectory().appendingPathComponent(StemJobFiles.heartbeatFilename))
    }

    func jobInput(for audioURL: URL, jobDirectory: URL, mode: StemJobInputMode) throws -> StemJobInput {
        switch mode {
        case .direct:
            return StemJobInput(audioPath: audioURL.path, stagedInputDirectory: nil)
        case .staged:
            let inputDirectory = jobDirectory.appendingPathComponent("input", isDirectory: true)
            try fileManager.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
            let destinationURL = inputDirectory.appendingPathComponent(audioURL.lastPathComponent)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: audioURL, to: destinationURL)
            return StemJobInput(audioPath: destinationURL.path, stagedInputDirectory: inputDirectory)
        }
    }

    static func defaultSandboxDetection() -> Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    func isInputPermissionFailure(_ error: Error, originalAudioPath: String) -> Bool {
        let details: String
        if case let StemSeparationError.helperJobFailed(errorDetails) = error {
            details = errorDetails
        } else {
            details = error.localizedDescription
        }

        return details.localizedCaseInsensitiveContains("Operation not permitted")
            && details.contains(originalAudioPath)
    }

    private func diagnostics(for jobDirectory: URL, status: StemJobStatus) -> String {
        let stdout = readTail(from: jobDirectory.appendingPathComponent(StemJobFiles.stdoutFilename))
        let stderr = readTail(from: jobDirectory.appendingPathComponent(StemJobFiles.stderrFilename))
        return [
            "job: \(jobDirectory.path)",
            "status: \(status.phase.rawValue)",
            "message: \(status.message)",
            status.backendCommand.map { "command: \($0)" },
            status.diagnostics.map { "diagnostics:\n\($0)" },
            stdout.isEmpty ? nil : "stdout:\n\(stdout)",
            stderr.isEmpty ? nil : "stderr:\n\(stderr)"
        ].compactMap { $0 }.joined(separator: "\n")
    }

    private func readTail(from url: URL) -> String {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return text.split(separator: "\n").suffix(12).joined(separator: "\n")
    }

    private func discoverCachedMetadata(matching fingerprint: StemSourceFingerprint, method: StemSeparationMethod? = nil) throws -> StemCacheMetadata? {
        let rootDirectory = applicationSupportDirectory()
            .appendingPathComponent(StemJobFiles.cacheDirectoryName, isDirectory: true)
        let cacheDirectories = ((try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? [])
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }

        for directory in cacheDirectories {
            if let metadata = try validatedMetadata(
                in: directory,
                expectedFingerprint: fingerprint,
                allowsPathMismatch: true,
                method: method
            ) {
                return metadata
            }
        }

        return nil
    }

    private func validatedMetadata(
        in cacheDirectory: URL,
        expectedFingerprint: StemSourceFingerprint,
        allowsPathMismatch: Bool = false,
        method: StemSeparationMethod? = nil
    ) throws -> StemCacheMetadata? {
        let metadataURL = cacheDirectory.appendingPathComponent("metadata.json")
        guard fileManager.fileExists(atPath: metadataURL.path) else { return nil }

        let data = try Data(contentsOf: metadataURL)
        var metadata = try JSONDecoder().decode(StemCacheMetadata.self, from: data)

        let sourceMatches = metadata.sourceFingerprint == expectedFingerprint
            || (allowsPathMismatch && metadata.sourceFingerprint.hasSameFileIdentity(as: expectedFingerprint))

        guard sourceMatches,
              metadata.settingsVersion == Self.settingsVersion
        else {
            return nil
        }
        if let method, !metadata.matches(method: method) {
            return nil
        }

        metadata.cacheKey = cacheDirectory.lastPathComponent
        metadata.sourceFingerprint = expectedFingerprint
        metadata.stems = try discoverStems(in: cacheDirectory, expectedTypes: metadata.expectedStemTypes)
        return metadata
    }

    private func discoverStems(in directory: URL, expectedTypes: [StemType]) throws -> [StemFile] {
        let files = (fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }) ?? []

        let stems = expectedTypes.compactMap { type -> StemFile? in
            guard let url = files.first(where: { $0.lastPathComponent.lowercased() == type.canonicalStemFilename }) else {
                return nil
            }
            return StemFile(type: type, url: url, displayName: type.title)
        }

        let missingTypes = expectedTypes.filter { type in
            !stems.contains(where: { $0.type == type })
        }
        guard missingTypes.isEmpty else {
            throw StemSeparationError.incompleteOutput(missingTypes)
        }

        return stems
    }

    private func validate(stems: [StemFile], originalDuration: TimeInterval) async throws {
        for stem in stems {
            guard fileManager.isReadableFile(atPath: stem.url.path) else {
                throw StemSeparationError.incompleteOutput([stem.type])
            }

            let asset = AVURLAsset(url: stem.url)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, abs(duration - originalDuration) < max(2, originalDuration * 0.02) else {
                throw StemSeparationError.invalidStemDuration(stem.type)
            }
        }
    }

    private func cacheKey(for fingerprint: StemSourceFingerprint, method: StemSeparationMethod) -> String {
        let rawValue = [
            fingerprint.path,
            String(fingerprint.fileSize),
            String(fingerprint.modificationTime),
            method.id,
            method.modelName,
            String(Self.settingsVersion)
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(rawValue.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func applicationSupportDirectory() -> URL {
        if let applicationSupportDirectoryOverride {
            return applicationSupportDirectoryOverride
        }
        return Self.applicationSupportDirectory(fileManager: fileManager)
    }

    private static func applicationSupportDirectory(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseURL.appendingPathComponent("JammLab", isDirectory: true)
    }

    private func cacheDirectory(for cacheKey: String) -> URL {
        applicationSupportDirectory()
            .appendingPathComponent(StemJobFiles.cacheDirectoryName, isDirectory: true)
            .appendingPathComponent(cacheKey, isDirectory: true)
    }

    private func jobsDirectory() -> URL {
        let directory = StemJobFiles.currentJobsDirectory(in: applicationSupportDirectory())
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func modelDirectory() -> URL {
        applicationSupportDirectory().appendingPathComponent(StemJobFiles.modelDirectoryName, isDirectory: true)
    }

    private func readJSON<T: Decodable>(from url: URL) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
