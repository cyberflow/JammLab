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

struct StemTranscriptionOverwriteRequest: Equatable {
    var stemType: StemType
    var projectURL: URL?
    var importedFileURL: URL?
    var stemURL: URL
    var sourceFingerprint: StemSourceFingerprint
    var configuration: StemTranscriptionConfiguration
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
    var notationPartID: NotationPartID
    var sourceFingerprint: StemSourceFingerprint
    var createdAt: Date
    var configuration: StemTranscriptionConfiguration
    /// Immutable detection provenance. Editable/quantized notation remains in
    /// the project's shared `notationItems` collection.
    var notes: [StemTranscriptionNote]
    var timings: StemTranscriptionTimings?
    var warnings: [String]

    init(
        id: UUID = UUID(),
        stemType: StemType,
        notationPartID: NotationPartID? = nil,
        sourceFingerprint: StemSourceFingerprint,
        createdAt: Date = Date(),
        configuration: StemTranscriptionConfiguration,
        notes: [StemTranscriptionNote],
        timings: StemTranscriptionTimings? = nil,
        warnings: [String] = []
    ) {
        self.id = id
        self.stemType = stemType
        self.notationPartID = notationPartID ?? .stem(stemType)
        self.sourceFingerprint = sourceFingerprint
        self.createdAt = createdAt
        self.configuration = configuration
        self.notes = notes
        self.timings = timings
        self.warnings = warnings
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case stemType
        case notationPartID
        case sourceFingerprint
        case createdAt
        case configuration
        case notes
        case timings
        case warnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        stemType = try container.decode(StemType.self, forKey: .stemType)
        notationPartID = try container.decodeIfPresent(
            NotationPartID.self,
            forKey: .notationPartID
        ) ?? .stem(stemType)
        sourceFingerprint = try container.decode(StemSourceFingerprint.self, forKey: .sourceFingerprint)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        configuration = try container.decode(
            StemTranscriptionConfiguration.self,
            forKey: .configuration
        )
        notes = try container.decode([StemTranscriptionNote].self, forKey: .notes)
        timings = try container.decodeIfPresent(StemTranscriptionTimings.self, forKey: .timings)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
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
