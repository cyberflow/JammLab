import Foundation

enum StemHelperLaunchError: LocalizedError {
    case missingExecutable(URL)
    case executableNotRunnable(URL)
    case launchFailed(URL, String)
    case heartbeatTimedOut(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let url):
            return "Stem helper could not be started automatically because the bundled helper is missing at \(url.path)."
        case .executableNotRunnable(let url):
            return "Stem helper could not be started automatically because the bundled helper is not executable at \(url.path)."
        case .launchFailed(_, let details):
            return "Stem helper could not be started automatically. \(details)"
        case .heartbeatTimedOut:
            return "Stem helper started, but did not become ready in time."
        }
    }

    var diagnostics: String {
        switch self {
        case .missingExecutable(let url):
            return "missing helper executable: \(url.path)"
        case .executableNotRunnable(let url):
            return "helper executable is not runnable: \(url.path)"
        case .launchFailed(let url, let details):
            return "helper launch failed: \(url.path)\n\(details)"
        case .heartbeatTimedOut(let details):
            return "helper heartbeat timed out\n\(details)"
        }
    }
}

protocol StemHelperLaunchedProcess: AnyObject {
    var isRunning: Bool { get }
    func terminate()
}

protocol StemHelperProcessLaunching {
    func launchStemHelper(at executableURL: URL) throws -> StemHelperLaunchedProcess
}

final class FoundationStemHelperLauncher: StemHelperProcessLaunching {
    func launchStemHelper(at executableURL: URL) throws -> StemHelperLaunchedProcess {
        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = executableURL.deletingLastPathComponent()
        process.environment = ProcessInfo.processInfo.environment

        do {
            try process.run()
        } catch {
            throw StemHelperLaunchError.launchFailed(executableURL, error.localizedDescription)
        }

        return FoundationStemHelperProcess(process: process)
    }
}

private final class FoundationStemHelperProcess: StemHelperLaunchedProcess {
    private let process: Process

    init(process: Process) {
        self.process = process
    }

    var isRunning: Bool {
        process.isRunning
    }

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }
}

final class StemHelperProcessController {
    private let helperExecutableURL: URL
    private let heartbeatURL: URL
    private let expectedHelperVersion: Int
    private let fileManager: FileManager
    private let launcher: StemHelperProcessLaunching
    private let pollInterval: UInt64 = 200_000_000
    private let lock = NSLock()
    private var launchedProcess: StemHelperLaunchedProcess?

    init(
        helperExecutableURL: URL = StemHelperProcessController.defaultHelperExecutableURL(),
        heartbeatURL: URL,
        expectedHelperVersion: Int = StemJobFiles.helperVersion,
        fileManager: FileManager = .default,
        launcher: StemHelperProcessLaunching = FoundationStemHelperLauncher()
    ) {
        self.helperExecutableURL = helperExecutableURL
        self.heartbeatURL = heartbeatURL
        self.expectedHelperVersion = expectedHelperVersion
        self.fileManager = fileManager
        self.launcher = launcher
    }

    deinit {
        lock.lock()
        let process = launchedProcess
        launchedProcess = nil
        lock.unlock()
        process?.terminate()
    }

    static func defaultHelperExecutableURL(bundle: Bundle = .main) -> URL {
        bundle.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("JammLabStemHelper")
    }

    func ensureRunning(timeout: TimeInterval = 3) async throws {
        if isHeartbeatFresh {
            return
        }

        try launchIfNeeded()
        try await waitForFreshHeartbeat(timeout: timeout)
    }

    private func launchIfNeeded() throws {
        lock.lock()
        if let launchedProcess, launchedProcess.isRunning {
            lock.unlock()
            return
        }
        launchedProcess = nil
        lock.unlock()

        guard fileManager.fileExists(atPath: helperExecutableURL.path) else {
            throw StemHelperLaunchError.missingExecutable(helperExecutableURL)
        }

        guard fileManager.isExecutableFile(atPath: helperExecutableURL.path) else {
            throw StemHelperLaunchError.executableNotRunnable(helperExecutableURL)
        }

        let process = try launcher.launchStemHelper(at: helperExecutableURL)

        lock.lock()
        launchedProcess = process
        lock.unlock()
    }

    private func waitForFreshHeartbeat(timeout: TimeInterval) async throws {
        let startedAt = Date()
        while Date().timeIntervalSince(startedAt) < timeout {
            if isHeartbeatFresh {
                return
            }

            try await Task.sleep(nanoseconds: pollInterval)
        }

        throw StemHelperLaunchError.heartbeatTimedOut("heartbeat: \(heartbeatURL.path)")
    }

    private var isHeartbeatFresh: Bool {
        guard let data = try? Data(contentsOf: heartbeatURL),
              let heartbeat = try? JSONDecoder().decode(StemHelperHeartbeat.self, from: data)
        else {
            return false
        }

        return heartbeat.helperVersion == expectedHelperVersion && heartbeat.isFresh
    }
}
