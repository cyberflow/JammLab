import Foundation

enum PlaybackMode: String, Codable, CaseIterable, Identifiable {
    case original
    case stems

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original:
            return "Original"
        case .stems:
            return "Stems"
        }
    }
}

enum StemType: String, Codable, CaseIterable, Identifiable {
    case vocals
    case drums
    case bass
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vocals:
            return "Vocals"
        case .drums:
            return "Drums"
        case .bass:
            return "Bass"
        case .other:
            return "Other"
        }
    }

    var demucsFilename: String {
        "\(rawValue).wav"
    }

    func matchesOutputFilename(_ filename: String) -> Bool {
        let name = filename.lowercased()
        guard name.hasSuffix(".wav") || name.hasSuffix(".flac") || name.hasSuffix(".mp3") else {
            return false
        }
        return name == demucsFilename || name.contains(rawValue)
    }
}

struct StemSourceFingerprint: Codable, Hashable {
    var path: String
    var fileSize: Int64
    var modificationTime: TimeInterval

    func hasSameFileIdentity(as other: StemSourceFingerprint) -> Bool {
        fileSize == other.fileSize && modificationTime == other.modificationTime
    }
}

struct StemFile: Codable, Equatable {
    var type: StemType
    var url: URL
    var displayName: String
}

struct StemMixItem: Codable, Equatable, Identifiable {
    var type: StemType
    var volume: Float
    var isMuted: Bool
    var isSoloed: Bool
    var isAvailable: Bool

    var id: StemType { type }

    init(
        type: StemType,
        volume: Float = AppSliderDefaults.stemTrackVolume,
        isMuted: Bool = false,
        isSoloed: Bool = false,
        isAvailable: Bool = false
    ) {
        self.type = type
        self.volume = min(1, max(0, volume))
        self.isMuted = isMuted
        self.isSoloed = isSoloed
        self.isAvailable = isAvailable
    }

    var effectiveVolume: Float {
        isMuted ? 0 : volume
    }
}

struct StemMixState: Codable, Equatable {
    var items: [StemMixItem]

    init(items: [StemMixItem] = StemType.allCases.map { StemMixItem(type: $0) }) {
        self.items = StemType.allCases.map { type in
            items.first(where: { $0.type == type }) ?? StemMixItem(type: type)
        }
    }

    var hasSolo: Bool {
        items.contains { $0.isSoloed }
    }

    func item(for type: StemType) -> StemMixItem {
        items.first(where: { $0.type == type }) ?? StemMixItem(type: type)
    }

    mutating func update(_ type: StemType, transform: (inout StemMixItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.type == type }) else { return }
        transform(&items[index])
        items[index].volume = min(1, max(0, items[index].volume))
    }

    mutating func setAvailability(from stems: [StemFile]) {
        let availableTypes = Set(stems.map(\.type))
        for index in items.indices {
            items[index].isAvailable = availableTypes.contains(items[index].type)
        }
    }

    mutating func resetMix(availableStems: [StemFile] = []) {
        items = StemType.allCases.map { StemMixItem(type: $0, volume: AppSliderDefaults.stemTrackVolume) }
        setAvailability(from: availableStems)
    }

    func isAudible(_ type: StemType) -> Bool {
        let item = item(for: type)
        guard item.isAvailable else { return false }
        return hasSolo ? item.isSoloed : !item.isMuted
    }

    func effectiveVolume(for type: StemType) -> Float {
        isAudible(type) ? item(for: type).volume : 0
    }
}

struct StemCacheMetadata: Codable, Equatable {
    var cacheKey: String
    var sourceFingerprint: StemSourceFingerprint
    var backendIdentifier: String
    var modelName: String
    var settingsVersion: Int
    var createdAt: Date
    var stems: [StemFile]
}

struct StemProjectState: Codable, Equatable {
    var cacheKey: String?
    var sourceFingerprint: StemSourceFingerprint?
    var backendIdentifier: String?
    var modelName: String?
    var settingsVersion: Int?
    var playbackMode: PlaybackMode
    var mixState: StemMixState

    init(
        cacheKey: String? = nil,
        sourceFingerprint: StemSourceFingerprint? = nil,
        backendIdentifier: String? = nil,
        modelName: String? = nil,
        settingsVersion: Int? = nil,
        playbackMode: PlaybackMode = .original,
        mixState: StemMixState = StemMixState()
    ) {
        self.cacheKey = cacheKey
        self.sourceFingerprint = sourceFingerprint
        self.backendIdentifier = backendIdentifier
        self.modelName = modelName
        self.settingsVersion = settingsVersion
        self.playbackMode = playbackMode
        self.mixState = mixState
    }
}

enum StemSeparationPhase: Equatable {
    case idle
    case checkingBackend
    case processing
    case completed
    case failed(String)
    case cancelled

    var title: String {
        switch self {
        case .idle:
            return "Idle"
        case .checkingBackend:
            return "Checking backend"
        case .processing:
            return "Processing"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }
}

struct StemSeparationViewState: Equatable {
    var phase: StemSeparationPhase = .idle
    var progress: Double?
    var status: String = "Stems unavailable"
    var diagnostics: String?

    var isProcessing: Bool {
        if case .checkingBackend = phase { return true }
        if case .processing = phase { return true }
        return false
    }
}
