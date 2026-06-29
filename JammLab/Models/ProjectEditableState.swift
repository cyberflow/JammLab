import Foundation

struct ProjectEditableState: Equatable {
    var notes: [TimecodedNote]
    var harmonySymbols: [HarmonySymbol] = []
    var projectKeySelection: ProjectKeySelection? = nil
    var selectedRegionID: TimecodedNote.ID?
    var selectedHarmonySymbolID: HarmonySymbol.ID?
    var activeLoopRegionID: TimecodedNote.ID?
    var loopRegion: LoopRegion
    var isLooping: Bool
    var tempoBPM: Double?
    var beatGridSettings: BeatGridSettings
    var playbackRate: Float
    var pitchShiftSemitones: Float
    var mainTrackVolume: Float
    var stemMixState: StemMixState
    var playbackMode: PlaybackMode
    var isClickEnabled: Bool
    var clickVolume: Float
    var isSnapEnabled: Bool
}

struct ProjectPersistedEditableState: Equatable {
    var notes: [TimecodedNote]
    var harmonySymbols: [HarmonySymbol] = []
    var projectKeySelection: ProjectKeySelection? = nil
    var loopRegion: LoopRegion
    var isLooping: Bool
    var tempoBPM: Double?
    var beatGridSettings: BeatGridSettings
    var playbackRate: Float
    var pitchShiftSemitones: Float
    var mainTrackVolume: Float
    var stemMixState: StemMixState
    var playbackMode: PlaybackMode
    var isClickEnabled: Bool
    var clickVolume: Float
    var isSnapEnabled: Bool
    var playbackMarkerTime: TimeInterval
    var timelineVisibleRange: ClosedRange<TimeInterval>
    var isVideoWindowOpen: Bool
}
