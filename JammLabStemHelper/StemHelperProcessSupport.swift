import Foundation

struct HelperBackend {
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

    func identifier(separatorVersion: String) -> String {
        "\(executableURL.lastPathComponent)/\(separatorVersion)"
    }
}

struct ProcessResult {
    var exitCode: Int32
    var output: String
}

enum HelperError: LocalizedError {
    case backendNotFound(String)
    case backendFailed(String)
    case incompleteOutput(String)
    case protocolMismatch(expected: Int, actual: Int)
    case unsupportedCapability(model: String, computeMode: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .backendNotFound(let details):
            return "Bundled stem separator was not found or failed capability probing.\n\(details)"
        case .backendFailed(let details):
            return "Stem backend failed.\n\(details)"
        case .incompleteOutput(let stem):
            return "Stem backend did not produce \(stem)."
        case .protocolMismatch(let expected, let actual):
            return "Stem job protocol mismatch: expected v\(expected), got v\(actual)."
        case .unsupportedCapability(let model, let computeMode):
            return "Bundled separator does not support model \(model) with compute mode \(computeMode)."
        case .cancelled:
            return "Stem helper job cancelled."
        }
    }
}

final class HeartbeatThread {
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

final class CancellationWatcherThread {
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
        FileManager.default.fileExists(
            atPath: jobDirectory.appendingPathComponent(StemJobFiles.cancelFilename).path
        )
    }
}

final class ProcessOutputBuffer: @unchecked Sendable {
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
