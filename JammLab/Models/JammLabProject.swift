import Foundation

struct ProjectTimelineVisibleRange: Codable, Equatable {
    var start: TimeInterval
    var end: TimeInterval

    init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }

    init(_ range: ClosedRange<TimeInterval>) {
        self.init(start: range.lowerBound, end: range.upperBound)
    }
}

struct JammLabProject: Codable {
    var formatVersion: Int
    var audioBookmarkData: Data
    var artifactRootBookmarkData: Data?
    var audioDisplayName: String
    var audioDuration: TimeInterval
    var mediaKind: ImportedMediaKind?
    var notes: [TimecodedNote]
    var harmonySymbols: [HarmonySymbol]
    var projectKeySelection: ProjectKeySelection?
    var loopStart: TimeInterval
    var loopEnd: TimeInterval
    var isLoopEnabled: Bool?
    var playbackRate: Float
    var pitchShiftSemitones: Float
    var tempoBPM: Double?
    var beatGridSettings: BeatGridSettings?
    var mainTrackVolume: Float?
    var isClickEnabled: Bool?
    var clickVolume: Float?
    var isSnapEnabled: Bool?
    var playbackMode: PlaybackMode?
    var playbackMarkerTime: TimeInterval?
    var timelineVisibleRange: ProjectTimelineVisibleRange?
    var stemState: StemProjectState?
    var isVideoWindowOpen: Bool?

    init(
        formatVersion: Int = 10,
        audioBookmarkData: Data,
        artifactRootBookmarkData: Data? = nil,
        audioDisplayName: String,
        audioDuration: TimeInterval,
        mediaKind: ImportedMediaKind? = nil,
        notes: [TimecodedNote],
        harmonySymbols: [HarmonySymbol] = [],
        projectKeySelection: ProjectKeySelection? = nil,
        loopStart: TimeInterval,
        loopEnd: TimeInterval,
        isLoopEnabled: Bool? = nil,
        playbackRate: Float,
        pitchShiftSemitones: Float,
        tempoBPM: Double? = nil,
        beatGridSettings: BeatGridSettings? = nil,
        mainTrackVolume: Float? = nil,
        isClickEnabled: Bool? = nil,
        clickVolume: Float? = nil,
        isSnapEnabled: Bool? = nil,
        playbackMode: PlaybackMode? = nil,
        playbackMarkerTime: TimeInterval? = nil,
        timelineVisibleRange: ProjectTimelineVisibleRange? = nil,
        stemState: StemProjectState? = nil,
        isVideoWindowOpen: Bool? = nil
    ) {
        self.formatVersion = formatVersion
        self.audioBookmarkData = audioBookmarkData
        self.artifactRootBookmarkData = artifactRootBookmarkData
        self.audioDisplayName = audioDisplayName
        self.audioDuration = audioDuration
        self.mediaKind = mediaKind
        self.notes = notes
        self.harmonySymbols = harmonySymbols
        self.projectKeySelection = projectKeySelection
        self.loopStart = loopStart
        self.loopEnd = loopEnd
        self.isLoopEnabled = isLoopEnabled
        self.playbackRate = playbackRate
        self.pitchShiftSemitones = pitchShiftSemitones
        self.tempoBPM = tempoBPM
        self.beatGridSettings = beatGridSettings
        self.mainTrackVolume = mainTrackVolume
        self.isClickEnabled = isClickEnabled
        self.clickVolume = clickVolume
        self.isSnapEnabled = isSnapEnabled
        self.playbackMode = playbackMode
        self.playbackMarkerTime = playbackMarkerTime
        self.timelineVisibleRange = timelineVisibleRange
        self.stemState = stemState
        self.isVideoWindowOpen = isVideoWindowOpen
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case audioBookmarkData
        case artifactRootBookmarkData
        case audioDisplayName
        case audioDuration
        case mediaKind
        case notes
        case harmonySymbols
        case projectKeySelection
        case loopStart
        case loopEnd
        case isLoopEnabled
        case playbackRate
        case pitchShiftSemitones
        case tempoBPM
        case beatGridSettings
        case mainTrackVolume
        case isClickEnabled
        case clickVolume
        case isSnapEnabled
        case playbackMode
        case playbackMarkerTime
        case timelineVisibleRange
        case stemState
        case isVideoWindowOpen
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        audioBookmarkData = try container.decode(Data.self, forKey: .audioBookmarkData)
        artifactRootBookmarkData = try container.decodeIfPresent(Data.self, forKey: .artifactRootBookmarkData)
        audioDisplayName = try container.decode(String.self, forKey: .audioDisplayName)
        audioDuration = try container.decode(TimeInterval.self, forKey: .audioDuration)
        mediaKind = try container.decodeIfPresent(ImportedMediaKind.self, forKey: .mediaKind)
        notes = try container.decode([TimecodedNote].self, forKey: .notes)
        harmonySymbols = try container.decodeIfPresent([HarmonySymbol].self, forKey: .harmonySymbols) ?? []
        projectKeySelection = try container.decodeIfPresent(ProjectKeySelection.self, forKey: .projectKeySelection)
        loopStart = try container.decode(TimeInterval.self, forKey: .loopStart)
        loopEnd = try container.decode(TimeInterval.self, forKey: .loopEnd)
        isLoopEnabled = try container.decodeIfPresent(Bool.self, forKey: .isLoopEnabled)
        playbackRate = try container.decode(Float.self, forKey: .playbackRate)
        pitchShiftSemitones = try container.decode(Float.self, forKey: .pitchShiftSemitones)
        tempoBPM = try container.decodeIfPresent(Double.self, forKey: .tempoBPM)
        beatGridSettings = try container.decodeIfPresent(BeatGridSettings.self, forKey: .beatGridSettings)
        mainTrackVolume = try container.decodeIfPresent(Float.self, forKey: .mainTrackVolume)
        isClickEnabled = try container.decodeIfPresent(Bool.self, forKey: .isClickEnabled)
        clickVolume = try container.decodeIfPresent(Float.self, forKey: .clickVolume)
        isSnapEnabled = try container.decodeIfPresent(Bool.self, forKey: .isSnapEnabled)
        playbackMode = try container.decodeIfPresent(PlaybackMode.self, forKey: .playbackMode)
        playbackMarkerTime = try container.decodeIfPresent(TimeInterval.self, forKey: .playbackMarkerTime)
        timelineVisibleRange = try container.decodeIfPresent(ProjectTimelineVisibleRange.self, forKey: .timelineVisibleRange)
        stemState = try container.decodeIfPresent(StemProjectState.self, forKey: .stemState)
        isVideoWindowOpen = try container.decodeIfPresent(Bool.self, forKey: .isVideoWindowOpen)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(audioBookmarkData, forKey: .audioBookmarkData)
        try container.encodeIfPresent(artifactRootBookmarkData, forKey: .artifactRootBookmarkData)
        try container.encode(audioDisplayName, forKey: .audioDisplayName)
        try container.encode(audioDuration, forKey: .audioDuration)
        try container.encodeIfPresent(mediaKind, forKey: .mediaKind)
        try container.encode(notes, forKey: .notes)
        try container.encode(harmonySymbols, forKey: .harmonySymbols)
        try container.encodeIfPresent(projectKeySelection, forKey: .projectKeySelection)
        try container.encode(loopStart, forKey: .loopStart)
        try container.encode(loopEnd, forKey: .loopEnd)
        try container.encodeIfPresent(isLoopEnabled, forKey: .isLoopEnabled)
        try container.encode(playbackRate, forKey: .playbackRate)
        try container.encode(pitchShiftSemitones, forKey: .pitchShiftSemitones)
        try container.encodeIfPresent(tempoBPM, forKey: .tempoBPM)
        try container.encodeIfPresent(beatGridSettings, forKey: .beatGridSettings)
        try container.encodeIfPresent(mainTrackVolume, forKey: .mainTrackVolume)
        try container.encodeIfPresent(isClickEnabled, forKey: .isClickEnabled)
        try container.encodeIfPresent(clickVolume, forKey: .clickVolume)
        try container.encodeIfPresent(isSnapEnabled, forKey: .isSnapEnabled)
        try container.encodeIfPresent(playbackMode, forKey: .playbackMode)
        try container.encodeIfPresent(playbackMarkerTime, forKey: .playbackMarkerTime)
        try container.encodeIfPresent(timelineVisibleRange, forKey: .timelineVisibleRange)
        try container.encodeIfPresent(stemState, forKey: .stemState)
        try container.encodeIfPresent(isVideoWindowOpen, forKey: .isVideoWindowOpen)
    }

    func resolvedAudioURL() throws -> URL {
        try resolvedMediaURL()
    }

    func resolvedMediaURL() throws -> URL {
        var isStale = false
        return try URL(
            resolvingBookmarkData: audioBookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    func resolvedArtifactRootURL() throws -> URL? {
        guard let artifactRootBookmarkData else { return nil }
        var isStale = false
        return try URL(
            resolvingBookmarkData: artifactRootBookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}
