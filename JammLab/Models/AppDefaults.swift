import Foundation

enum AppDefaults {
    static let defaultTempoBPM: Double = 120
    static let startupGridDuration: TimeInterval = 60
}

enum AppSliderDefaults {
    static let minimumPlaybackRate: Float = 0.25
    static let maximumPlaybackRate: Float = 1
    static let playbackRate: Float = 1
    static let minimumPitchShiftSemitones: Float = -12
    static let maximumPitchShiftSemitones: Float = 12
    static let pitchShiftSemitones: Float = 0
    static let mainTrackVolume: Float = 0.75
    static let stemTrackVolume: Float = 0.75
    static let clickVolume: Float = 0.75
}
