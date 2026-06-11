import Foundation

@MainActor
protocol AudioPlaybackControlling: AnyObject {
    var isLoaded: Bool { get }
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get }

    func load(url: URL) throws
    func play() throws
    func pause()
    func stop()
    func unload()
    func seek(to time: TimeInterval)
    func setLoop(enabled: Bool, region: LoopRegion)
    func setPlaybackRate(_ rate: Float)
    func setPitchShift(semitones: Float)
    func setMainVolume(_ volume: Float)
    func load(stems: [StemFile], mixState: StemMixState) throws
    func applyMix(_ mixState: StemMixState)
    func setClickEnabled(_ isEnabled: Bool)
    func setClickVolume(_ volume: Float)
    func setClickSettings(_ settings: BeatGridSettings)
    func setClickSoundSettings(_ settings: ClickSoundSettings)
    func setAudioOutputDevice(uid: String?) throws
    func resetClickSchedule()
}

extension AudioPlaybackControlling {
    func load(stems: [StemFile], mixState: StemMixState) throws {
        throw MultiTrackAudioPlayerError.unsupportedStemLoad
    }

    func setLoop(enabled: Bool, region: LoopRegion) {}
    func applyMix(_ mixState: StemMixState) {}
    func setMainVolume(_ volume: Float) {}
    func setClickEnabled(_ isEnabled: Bool) {}
    func setClickVolume(_ volume: Float) {}
    func setClickSettings(_ settings: BeatGridSettings) {}
    func setClickSoundSettings(_ settings: ClickSoundSettings) {}
    func setAudioOutputDevice(uid: String?) throws {}
    func resetClickSchedule() {}
}
