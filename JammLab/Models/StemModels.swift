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
    case instrumental
    case drums
    case bass
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vocals:
            return "Vocals"
        case .instrumental:
            return "Instrumental"
        case .drums:
            return "Drums"
        case .bass:
            return "Bass"
        case .other:
            return "Other"
        }
    }

    var canonicalStemFilename: String {
        "\(rawValue).wav"
    }

    func matchesOutputFilename(_ filename: String) -> Bool {
        let name = filename.lowercased()
        guard name.hasSuffix(".wav") || name.hasSuffix(".flac") || name.hasSuffix(".mp3") else {
            return false
        }
        if self == .instrumental {
            return name == canonicalStemFilename
                || name.contains("instrumental")
                || name.contains("instrument")
                || name.contains("no_vocals")
                || name.contains("no-vocals")
        }
        return name == canonicalStemFilename || name.contains(rawValue)
    }
}

struct StemSeparationMethod: Equatable, Identifiable {
    let id: String
    let title: String
    let description: String
    let modelName: String
    let stemTypes: [StemType]

    var stemCountSummary: String {
        let stemCountLabel = stemTypes.count == 1 ? "1 stem" : "\(stemTypes.count) stems"
        return "\(stemCountLabel): \(stemTypes.englishList)."
    }

    var optionDescription: String {
        "\(stemCountSummary) \(description)"
    }

    static let vocalInstrumental = StemSeparationMethod(
        id: "vocalInstrumental",
        title: "Vocals + Instrumental",
        description: "Separate the track into vocals and a combined instrumental stem.",
        modelName: "UVR-MDX-NET-Inst_HQ_5.onnx",
        stemTypes: [.vocals, .instrumental]
    )

    static let fourStem = StemSeparationMethod(
        id: "fourStem",
        title: "Vocals + Bass + Drums + Other",
        description: "Separate the track into the current four-stem practice layout.",
        modelName: "htdemucs.yaml",
        stemTypes: [.vocals, .bass, .drums, .other]
    )

    static let allCases: [StemSeparationMethod] = [.vocalInstrumental, .fourStem]
    static let defaultValue = fourStem

    static func method(forID id: String?) -> StemSeparationMethod? {
        guard let id else { return nil }
        return allCases.first { $0.id == id }
    }

    static func method(forModelName modelName: String) -> StemSeparationMethod? {
        allCases.first { $0.modelName == modelName }
    }
}

private extension Array where Element == StemType {
    var englishList: String {
        let titles = map { $0.title.lowercased() }
        switch titles.count {
        case 0:
            return ""
        case 1:
            return titles[0]
        case 2:
            return "\(titles[0]) and \(titles[1])"
        default:
            return "\(titles.dropLast().joined(separator: ", ")), and \(titles[titles.count - 1])"
        }
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
    var separationMethodID: String? = nil
    var modelName: String
    var settingsVersion: Int
    var createdAt: Date
    var stems: [StemFile]

    var expectedStemTypes: [StemType] {
        StemSeparationMethod.method(forID: separationMethodID)?.stemTypes
            ?? StemSeparationMethod.method(forModelName: modelName)?.stemTypes
            ?? StemSeparationMethod.defaultValue.stemTypes
    }

    func matches(method: StemSeparationMethod) -> Bool {
        if let separationMethodID {
            return separationMethodID == method.id && modelName == method.modelName
        }
        return method == .fourStem && modelName == method.modelName
    }
}

struct StemProjectState: Codable, Equatable {
    var cacheKey: String?
    var sourceFingerprint: StemSourceFingerprint?
    var backendIdentifier: String?
    var separationMethodID: String?
    var modelName: String?
    var settingsVersion: Int?
    var playbackMode: PlaybackMode
    var mixState: StemMixState

    init(
        cacheKey: String? = nil,
        sourceFingerprint: StemSourceFingerprint? = nil,
        backendIdentifier: String? = nil,
        separationMethodID: String? = nil,
        modelName: String? = nil,
        settingsVersion: Int? = nil,
        playbackMode: PlaybackMode = .original,
        mixState: StemMixState = StemMixState()
    ) {
        self.cacheKey = cacheKey
        self.sourceFingerprint = sourceFingerprint
        self.backendIdentifier = backendIdentifier
        self.separationMethodID = separationMethodID
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
