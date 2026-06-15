import Foundation

StemHelperRunner().run()

private final class StemHelperRunner {
    private let fileManager = FileManager.default
    private var activeProcess: Process?

    func run() {
        print("JammLabStemHelper started. Watching \(jobsDirectory().path)")
        try? fileManager.createDirectory(at: jobsDirectory(), withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: modelDirectory(), withIntermediateDirectories: true)

        while true {
            writeHeartbeat(activeJobID: nil)
            processPendingJobs()
            Thread.sleep(forTimeInterval: 1)
        }
    }

    private func processPendingJobs() {
        let jobDirectories = ((try? fileManager.contentsOfDirectory(
            at: jobsDirectory(),
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? [])
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for jobDirectory in jobDirectories {
            guard shouldProcess(jobDirectory) else { continue }
            process(jobDirectory)
        }
    }

    private func shouldProcess(_ jobDirectory: URL) -> Bool {
        let requestURL = jobDirectory.appendingPathComponent(StemJobFiles.requestFilename)
        let resultURL = jobDirectory.appendingPathComponent(StemJobFiles.resultFilename)
        let status: StemJobStatus? = try? readJSON(from: jobDirectory.appendingPathComponent(StemJobFiles.statusFilename))
        guard fileManager.fileExists(atPath: requestURL.path),
              !fileManager.fileExists(atPath: resultURL.path)
        else {
            return false
        }
        return status?.phase != .failed && status?.phase != .cancelled && status?.phase != .completed
    }

    private func process(_ jobDirectory: URL) {
        do {
            let request: StemJobRequest = try readJSON(from: jobDirectory.appendingPathComponent(StemJobFiles.requestFilename))
            writeHeartbeat(activeJobID: request.jobID)
            try updateStatus(.checkingBackend, request: request, jobDirectory: jobDirectory, message: "Checking backend")

            let backend = try resolveBackend(jobDirectory: jobDirectory)
            try ensureNotCancelled(jobDirectory)
            try updateStatus(
                .processing,
                request: request,
                jobDirectory: jobDirectory,
                message: "Separating stems",
                command: backend.commandDescription(extraArguments: separationArguments(for: request, jobDirectory: jobDirectory))
            )

            let workDirectory = jobDirectory.appendingPathComponent("output", isDirectory: true)
            if fileManager.fileExists(atPath: workDirectory.path) {
                try fileManager.removeItem(at: workDirectory)
            }
            try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)

            let result = try runBackend(
                backend,
                arguments: separationArguments(for: request, jobDirectory: jobDirectory),
                jobDirectory: jobDirectory,
                heartbeatJobID: request.jobID
            )

            try ensureNotCancelled(jobDirectory)
            guard result.exitCode == 0 else {
                throw HelperError.backendFailed(
                    [
                        "exitCode: \(result.exitCode)",
                        architectureHint(from: result.output),
                        tail(from: result.output)
                    ].compactMap { $0 }.joined(separator: "\n")
                )
            }

            let stems = try normalizeStems(
                from: workDirectory,
                cacheDirectory: URL(fileURLWithPath: request.cacheDirectoryPath),
                expectedTypes: request.expectedStemTypes ?? StemSeparationMethod.defaultValue.stemTypes
            )
            let metadata = StemCacheMetadata(
                cacheKey: request.cacheKey,
                sourceFingerprint: request.sourceFingerprint,
                backendIdentifier: backend.displayName,
                separationMethodID: request.separationMethodID,
                modelName: request.modelName,
                settingsVersion: request.settingsVersion,
                createdAt: Date(),
                stems: stems
            )

            try writeJSON(metadata, to: URL(fileURLWithPath: request.cacheDirectoryPath).appendingPathComponent("metadata.json"))
            let jobResult = StemJobResult(jobID: request.jobID, cacheKey: request.cacheKey, metadata: metadata, completedAt: Date())
            try writeJSON(jobResult, to: jobDirectory.appendingPathComponent(StemJobFiles.resultFilename))
            try updateStatus(.completed, request: request, jobDirectory: jobDirectory, message: "Stems ready", progress: 1)
        } catch HelperError.cancelled {
            markCancelled(jobDirectory)
        } catch {
            markFailed(jobDirectory, error: error)
        }
    }

    private func resolveBackend(jobDirectory: URL) throws -> HelperBackend {
        let candidates = StemBackendResolver().bundledSeparatorCandidates.map(HelperBackend.init(candidate:))

        var diagnostics: [String] = []
        for backend in candidates {
            do {
                let result = try runBackend(
                    backend,
                    arguments: ["--env_info"],
                    jobDirectory: jobDirectory,
                    heartbeatJobID: nil
                )
                guard result.exitCode == 0 else {
                    diagnostics.append("\(backend.commandDescription(extraArguments: ["--env_info"])) failed with \(result.exitCode)")
                    continue
                }
                if !result.output.localizedCaseInsensitiveContains("JammLabSeparatorHelper") {
                    diagnostics.append("\(backend.displayName) did not report bundled helper identity")
                }
                return backend
            } catch {
                diagnostics.append("\(backend.displayName): \(error.localizedDescription)")
            }
        }

        throw HelperError.backendNotFound(diagnostics.joined(separator: "\n"))
    }

    private func separationArguments(for request: StemJobRequest, jobDirectory: URL) -> [String] {
        let outputDirectory = jobDirectory.appendingPathComponent("output", isDirectory: true)
        return [
            request.audioPath,
            "-m",
            request.modelName,
            "--output_format",
            "WAV",
            "--output_dir",
            outputDirectory.path,
            "--model_file_dir",
            request.modelDirectoryPath,
            "--compute_device",
            request.computeMode ?? "cpu"
        ]
    }

    private func runBackend(
        _ backend: HelperBackend,
        arguments: [String],
        jobDirectory: URL,
        heartbeatJobID: String?
    ) throws -> ProcessResult {
        let process = Process()
        let executableURL = backend.executableURL

        process.executableURL = executableURL
        process.arguments = backend.argumentsPrefix + arguments
        process.environment = processEnvironment()

        let command = backend.commandDescription(executableURL: executableURL, extraArguments: arguments)
        append(command + "\n", to: jobDirectory.appendingPathComponent(StemJobFiles.stdoutFilename))

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        activeProcess = process
        let outputBuffer = ProcessOutputBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                outputBuffer.append(data)
            }
        }

        let heartbeatThread = HeartbeatThread { [weak self] in
            self?.writeHeartbeat(activeJobID: heartbeatJobID)
        }
        let cancellationWatcher = CancellationWatcherThread(jobDirectory: jobDirectory) { [weak self, weak process] in
            process?.terminate()
            self?.activeProcess = nil
        }
        heartbeatThread.start()
        cancellationWatcher.start()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            heartbeatThread.stop()
            cancellationWatcher.stop()
            activeProcess = nil
            throw error
        }

        heartbeatThread.stop()
        cancellationWatcher.stop()
        pipe.fileHandleForReading.readabilityHandler = nil
        let remainingData = pipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingData.isEmpty {
            outputBuffer.append(remainingData)
        }
        let output = outputBuffer.stringValue
        append(output, to: jobDirectory.appendingPathComponent(StemJobFiles.stdoutFilename))
        activeProcess = nil
        if fileManager.fileExists(atPath: jobDirectory.appendingPathComponent(StemJobFiles.cancelFilename).path) {
            throw HelperError.cancelled
        }
        return ProcessResult(exitCode: process.terminationStatus, output: output)
    }

    private func normalizeStems(
        from outputDirectory: URL,
        cacheDirectory: URL,
        expectedTypes: [StemType] = StemSeparationMethod.defaultValue.stemTypes
    ) throws -> [StemFile] {
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let files = (fileManager.enumerator(at: outputDirectory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }) ?? []

        return try expectedTypes.map { type in
            guard let sourceURL = files.first(where: { matches($0, type: type) }) else {
                throw HelperError.incompleteOutput(type.rawValue)
            }

            let destinationURL = cacheDirectory.appendingPathComponent(type.canonicalStemFilename)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return StemFile(type: type, url: destinationURL, displayName: type.title)
        }
    }

    private func matches(_ url: URL, type: StemType) -> Bool {
        let name = url.lastPathComponent.lowercased()
        guard name.hasSuffix(".wav") || name.hasSuffix(".flac") || name.hasSuffix(".mp3") else { return false }
        return type.matchesOutputFilename(name)
    }

    private func architectureHint(from output: String) -> String? {
        guard output.localizedCaseInsensitiveContains("incompatible architecture") else {
            return nil
        }

        return """
        Backend architecture mismatch detected in bundled separator runtime. Rebuild JammLabSeparatorHelper for the current Mac architecture.
        """
    }

    private func tail(from output: String) -> String {
        let lines = output.split(separator: "\n").suffix(16)
        return lines.isEmpty ? "No backend output." : lines.joined(separator: "\n")
    }

    private func updateStatus(
        _ phase: StemJobPhase,
        request: StemJobRequest,
        jobDirectory: URL,
        message: String,
        progress: Double? = nil,
        diagnostics: String? = nil,
        command: String? = nil
    ) throws {
        let status = StemJobStatus(
            jobID: request.jobID,
            phase: phase,
            progress: progress,
            message: message,
            diagnostics: diagnostics,
            backendCommand: command,
            updatedAt: Date()
        )
        try writeJSON(status, to: jobDirectory.appendingPathComponent(StemJobFiles.statusFilename))
    }

    private func markCancelled(_ jobDirectory: URL) {
        let jobID = jobDirectory.lastPathComponent
        let status = StemJobStatus(
            jobID: jobID,
            phase: .cancelled,
            progress: nil,
            message: "Stem separation cancelled",
            diagnostics: nil,
            backendCommand: nil,
            updatedAt: Date()
        )
        try? writeJSON(status, to: jobDirectory.appendingPathComponent(StemJobFiles.statusFilename))
    }

    private func markFailed(_ jobDirectory: URL, error: Error) {
        let jobID = jobDirectory.lastPathComponent
        let status = StemJobStatus(
            jobID: jobID,
            phase: .failed,
            progress: nil,
            message: error.localizedDescription,
            diagnostics: error.localizedDescription,
            backendCommand: nil,
            updatedAt: Date()
        )
        try? writeJSON(status, to: jobDirectory.appendingPathComponent(StemJobFiles.statusFilename))
        append(error.localizedDescription + "\n", to: jobDirectory.appendingPathComponent(StemJobFiles.stderrFilename))
    }

    private func ensureNotCancelled(_ jobDirectory: URL) throws {
        if fileManager.fileExists(atPath: jobDirectory.appendingPathComponent(StemJobFiles.cancelFilename).path) {
            activeProcess?.terminate()
            throw HelperError.cancelled
        }
    }

    private func writeHeartbeat(activeJobID: String?) {
        let heartbeat = StemHelperHeartbeat(
            helperVersion: StemJobFiles.helperVersion,
            updatedAt: Date(),
            activeJobID: activeJobID
        )
        try? writeJSON(heartbeat, to: jobsDirectory().appendingPathComponent(StemJobFiles.heartbeatFilename))
    }

    private func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONNOUSERSITE"] = "1"
        return environment
    }

    private func applicationSupportDirectory() -> URL {
        let containerSupportDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.cyberflow.JammLab/Data/Library/Application Support", isDirectory: true)
        if fileManager.fileExists(atPath: containerSupportDirectory.path) {
            return containerSupportDirectory.appendingPathComponent("JammLab", isDirectory: true)
        }

        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseURL.appendingPathComponent("JammLab", isDirectory: true)
    }

    private func jobsDirectory() -> URL {
        StemJobFiles.currentJobsDirectory(in: applicationSupportDirectory())
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

    private func append(_ text: String, to url: URL) {
        let data = Data(text.utf8)
        if fileManager.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}

private struct HelperBackend {
    var executableURL: URL
    var argumentsPrefix: [String]
    var displayName: String

    init(candidate: StemBackendCandidate) {
        executableURL = candidate.executableURL
        argumentsPrefix = candidate.argumentsPrefix
        displayName = candidate.displayName
    }

    func commandDescription(extraArguments: [String]) -> String {
        commandDescription(executableURL: executableURL, extraArguments: extraArguments)
    }

    func commandDescription(executableURL: URL, extraArguments: [String]) -> String {
        ([executableURL.path] + argumentsPrefix + extraArguments)
            .map { $0.contains(" ") ? "\"\($0)\"" : $0 }
            .joined(separator: " ")
    }

}

private struct ProcessResult {
    var exitCode: Int32
    var output: String
}

private enum HelperError: LocalizedError {
    case backendNotFound(String)
    case backendFailed(String)
    case incompleteOutput(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .backendNotFound(let details):
            return "Bundled stem separator was not found or failed --env_info.\n\(details)"
        case .backendFailed(let details):
            return "Stem backend failed.\n\(details)"
        case .incompleteOutput(let stem):
            return "Stem backend did not produce \(stem)."
        case .cancelled:
            return "Stem helper job cancelled."
        }
    }
}

private final class HeartbeatThread {
    private let lock = NSLock()
    private var isStopped = false
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func start() {
        Thread.detachNewThread { [weak self] in
            while self?.stopped == false {
                self?.action()
                Thread.sleep(forTimeInterval: 2)
            }
        }
    }

    func stop() {
        lock.lock()
        isStopped = true
        lock.unlock()
    }

    private var stopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isStopped
    }
}

private final class CancellationWatcherThread {
    private let lock = NSLock()
    private var isStopped = false
    private let jobDirectory: URL
    private let action: () -> Void

    init(jobDirectory: URL, action: @escaping () -> Void) {
        self.jobDirectory = jobDirectory
        self.action = action
    }

    func start() {
        Thread.detachNewThread { [weak self] in
            while self?.stopped == false {
                if self?.isCancelled == true {
                    self?.action()
                    self?.stop()
                    return
                }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }

    func stop() {
        lock.lock()
        isStopped = true
        lock.unlock()
    }

    private var stopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isStopped
    }

    private var isCancelled: Bool {
        FileManager.default.fileExists(atPath: jobDirectory.appendingPathComponent(StemJobFiles.cancelFilename).path)
    }
}

private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var stringValue: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        lock.unlock()
    }
}
