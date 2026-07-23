import Foundation

enum StemTranscriptionPhase: String, Codable, Equatable {
    case idle
    case preparingAudio
    case loadingModel
    case transcribing
    case processingNotes
    case completed
    case failed
    case cancelled
}

struct StemTranscriptionViewState: Equatable {
    var phase: StemTranscriptionPhase = .idle
    var progress: Double = 0
    var status: String = ""

    var isRunning: Bool {
        switch phase {
        case .preparingAudio, .loadingModel, .transcribing, .processingNotes:
            return true
        default:
            return false
        }
    }
}

struct StemTranscriptionConfiguration: Codable, Equatable {
    var minimumNoteDurationMilliseconds: Double = 125
    var noteSensitivity: Double = 0.7
    var splitSensitivity: Double = 0.5
    var includePitchBends = false
    var quantizationDenominator = 16

    static let neuralNoteDefaults = StemTranscriptionConfiguration()
}

struct StemTranscriptionNote: Codable, Equatable, Identifiable {
    var id: UUID
    var midiPitch: Int
    var rawStartTimeSeconds: TimeInterval
    var rawEndTimeSeconds: TimeInterval
    var projectStartTimeSeconds: TimeInterval
    var projectEndTimeSeconds: TimeInterval
    var confidence: Double
    var pitchBends: [Int]
    var notationItemIDs: [String]

    init(
        id: UUID = UUID(),
        midiPitch: Int,
        rawStartTimeSeconds: TimeInterval,
        rawEndTimeSeconds: TimeInterval,
        projectStartTimeSeconds: TimeInterval,
        projectEndTimeSeconds: TimeInterval,
        confidence: Double,
        pitchBends: [Int] = [],
        notationItemIDs: [String] = []
    ) {
        self.id = id
        self.midiPitch = midiPitch
        self.rawStartTimeSeconds = rawStartTimeSeconds
        self.rawEndTimeSeconds = rawEndTimeSeconds
        self.projectStartTimeSeconds = projectStartTimeSeconds
        self.projectEndTimeSeconds = projectEndTimeSeconds
        self.confidence = confidence
        self.pitchBends = pitchBends
        self.notationItemIDs = notationItemIDs
    }
}

struct StemTranscriptionTimings: Codable, Equatable {
    var audioPreparationSeconds: Double
    var modelLoadSeconds: Double
    var inferenceSeconds: Double
    var postProcessingSeconds: Double
    var totalSeconds: Double
    var processedDurationSeconds: Double

    var processingTimeRatio: Double {
        guard processedDurationSeconds > 0 else { return 0 }
        return totalSeconds / processedDurationSeconds
    }
}

struct StemTranscriptionTrack: Codable, Equatable, Identifiable {
    var id: UUID
    var stemType: StemType
    var sourceFingerprint: StemSourceFingerprint
    var createdAt: Date
    var configuration: StemTranscriptionConfiguration
    var notes: [StemTranscriptionNote]
    var timings: StemTranscriptionTimings?

    init(
        id: UUID = UUID(),
        stemType: StemType,
        sourceFingerprint: StemSourceFingerprint,
        createdAt: Date = Date(),
        configuration: StemTranscriptionConfiguration,
        notes: [StemTranscriptionNote],
        timings: StemTranscriptionTimings? = nil
    ) {
        self.id = id
        self.stemType = stemType
        self.sourceFingerprint = sourceFingerprint
        self.createdAt = createdAt
        self.configuration = configuration
        self.notes = notes
        self.timings = timings
    }

    var notationItemIDs: Set<String> {
        Set(notes.flatMap(\.notationItemIDs))
    }
}

struct StemTimelineMapping: Equatable {
    var sourceStartTime: TimeInterval
    var sourceDuration: TimeInterval
    var projectStartTime: TimeInterval
    var projectDuration: TimeInterval

    static func aligned(duration: TimeInterval) -> StemTimelineMapping {
        StemTimelineMapping(
            sourceStartTime: 0,
            sourceDuration: duration,
            projectStartTime: 0,
            projectDuration: duration
        )
    }

    func projectTime(forSourceTime sourceTime: TimeInterval) -> TimeInterval {
        guard sourceDuration > 0 else { return projectStartTime }
        let sourceProgress = (sourceTime - sourceStartTime) / sourceDuration
        return projectStartTime + sourceProgress * projectDuration
    }
}

enum StemTranscriptionConflictChoice: Equatable {
    case replace
    case createNew
    case cancel
}
