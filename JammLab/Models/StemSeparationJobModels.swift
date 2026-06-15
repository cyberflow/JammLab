import Foundation

enum StemJobPhase: String, Codable, Equatable {
    case pending
    case checkingBackend
    case processing
    case completed
    case failed
    case cancelled

    var viewPhase: StemSeparationPhase {
        switch self {
        case .pending:
            return .checkingBackend
        case .checkingBackend:
            return .checkingBackend
        case .processing:
            return .processing
        case .completed:
            return .completed
        case .failed:
            return .failed("Stem helper job failed")
        case .cancelled:
            return .cancelled
        }
    }
}

struct StemJobRequest: Codable, Equatable {
    var jobID: String
    var audioPath: String
    var cacheKey: String
    var cacheDirectoryPath: String
    var modelDirectoryPath: String
    var sourceFingerprint: StemSourceFingerprint
    var separationMethodID: String? = nil
    var expectedStemTypes: [StemType]? = nil
    var modelName: String
    var settingsVersion: Int
    var audioSeparatorPath: String?
    var audioSeparatorBookmarkData: Data?
    var computeMode: String?
    var createdAt: Date
}

struct StemJobStatus: Codable, Equatable {
    var jobID: String
    var phase: StemJobPhase
    var progress: Double?
    var message: String
    var diagnostics: String?
    var backendCommand: String?
    var updatedAt: Date

    static func pending(jobID: String) -> StemJobStatus {
        StemJobStatus(
            jobID: jobID,
            phase: .pending,
            progress: nil,
            message: "Waiting for helper",
            diagnostics: nil,
            backendCommand: nil,
            updatedAt: Date()
        )
    }
}

struct StemJobResult: Codable, Equatable {
    var jobID: String
    var cacheKey: String
    var metadata: StemCacheMetadata
    var completedAt: Date
}

struct StemHelperHeartbeat: Codable, Equatable {
    var helperVersion: Int
    var updatedAt: Date
    var activeJobID: String?

    var isFresh: Bool {
        Date().timeIntervalSince(updatedAt) < 8
    }
}

enum StemJobFiles {
    static let helperVersion = 4
    static let jobsDirectoryName = "StemJobs"
    static let currentJobsDirectoryName = "v\(helperVersion)"
    static let cacheDirectoryName = "StemCache"
    static let modelDirectoryName = "StemModels"
    static let requestFilename = "request.json"
    static let statusFilename = "status.json"
    static let resultFilename = "result.json"
    static let heartbeatFilename = "helper-heartbeat.json"
    static let cancelFilename = "cancel.request"
    static let stdoutFilename = "stdout.log"
    static let stderrFilename = "stderr.log"

    static func currentJobsDirectory(in applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory
            .appendingPathComponent(jobsDirectoryName, isDirectory: true)
            .appendingPathComponent(currentJobsDirectoryName, isDirectory: true)
    }
}
