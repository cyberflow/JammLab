import Foundation

struct JammLabProject: Codable {
    var formatVersion: Int
    var audioBookmarkData: Data
    var artifactRootBookmarkData: Data?
    var audioDisplayName: String
    var audioDuration: TimeInterval
    var mediaKind: ImportedMediaKind?
    var notes: [TimecodedNote]
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
    var stemState: StemProjectState?
    var isVideoWindowOpen: Bool?

    init(
        formatVersion: Int = 8,
        audioBookmarkData: Data,
        artifactRootBookmarkData: Data? = nil,
        audioDisplayName: String,
        audioDuration: TimeInterval,
        mediaKind: ImportedMediaKind? = nil,
        notes: [TimecodedNote],
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
        self.stemState = stemState
        self.isVideoWindowOpen = isVideoWindowOpen
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
