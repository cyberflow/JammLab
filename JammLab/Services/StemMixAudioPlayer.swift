@preconcurrency import AVFoundation
import AudioToolbox
import Foundation

enum MultiTrackAudioPlayerError: LocalizedError {
    case noStems
    case unsupportedStemLoad
    case unsupportedAudioFormat
    case audioConversionFailed
    case outputDeviceUnavailable

    var errorDescription: String? {
        switch self {
        case .noStems:
            return "No stems are available for playback."
        case .unsupportedStemLoad:
            return "This playback engine does not support separated stem files."
        case .unsupportedAudioFormat:
            return "The audio format is not supported for multi-track playback."
        case .audioConversionFailed:
            return "Audio decoding failed."
        case .outputDeviceUnavailable:
            return "Audio output device is unavailable."
        }
    }
}

@MainActor
final class MultiTrackAudioPlayer: AudioPlaybackControlling {
    enum TrackID: Hashable {
        case original
        case stem(StemType)
    }

    private var engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var timePitch = AVAudioUnitTimePitch()
    private var clickNode: AVAudioSourceNode?
    private var renderTracks: [TrackID: AudioRenderTrack] = [:]
    private var trackOrder: [AudioRenderTrack] = []
    private var outputFormat: AVAudioFormat?
    private let transportState = AudioTransportRenderState()
    private let clickState = ClickRenderState()
    private let audioDeviceService = AudioDeviceService()
    private var duration: TimeInterval = 0
    private var durationFrames: AVAudioFramePosition = 0
    private var playbackRate: Float = 1
    private var pitchShiftSemitones: Float = 0
    private var mainVolume: Float = 1
    private var clickSettings = BeatGridSettings()
    private var clickTempoMap: TempoMap?
    private var isClickEnabled = false
    private var clickVolume: Float = 0.65
    private var clickSoundSettings = ClickSoundSettings.defaultValue
    private var outputDeviceUID: String?
    private var isLoopEnabled = false
    private var loopRegion: LoopRegion = .empty

    private(set) var isLoaded = false
    private(set) var isPlaying = false

    var currentTime: TimeInterval {
        guard isLoaded, let outputFormat else { return 0 }
        let frame = transportState.currentFrame
        return min(duration, max(0, TimeInterval(frame) / outputFormat.sampleRate))
    }

    deinit {
        engine.stop()
    }

    func load(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let format = try renderFormat(for: file.processingFormat)
        let track = try renderTrack(id: .original, url: url, outputFormat: format, volume: mainVolume)
        try loadTracks([track], outputFormat: format)
    }

    func load(stems: [StemFile], mixState: StemMixState) throws {
        guard !stems.isEmpty else {
            throw MultiTrackAudioPlayerError.noStems
        }

        let firstFile = try AVAudioFile(forReading: stems[0].url)
        let format = try renderFormat(for: firstFile.processingFormat)
        let tracks = try stems.map { stem in
            try renderTrack(
                id: .stem(stem.type),
                url: stem.url,
                outputFormat: format,
                volume: mixState.effectiveVolume(for: stem.type)
            )
        }
        try loadTracks(tracks, outputFormat: format)
    }

    func play() throws {
        guard isLoaded else { return }

        if !engine.isRunning {
            try engine.start()
        }

        transportState.play()
        clickState.play(startFrame: transportState.currentFrame)
        isPlaying = true
    }

    func pause() {
        guard isLoaded else { return }

        transportState.pause()
        clickState.pause(at: transportState.currentFrame)
        isPlaying = false
    }

    func stop() {
        guard isLoaded else { return }

        transportState.stop()
        clickState.stop()
        isPlaying = false
    }

    func unload() {
        resetEngine()
    }

    func seek(to time: TimeInterval) {
        guard isLoaded, let outputFormat else { return }

        let frame = frame(for: time, sampleRate: outputFormat.sampleRate)
        transportState.seek(to: frame)
        clickState.seek(to: frame)
    }

    func setLoop(enabled: Bool, region: LoopRegion) {
        isLoopEnabled = enabled
        loopRegion = region
        applyLoopState()
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = ProjectStateNormalizer.normalizedPlaybackRate(rate)
        timePitch.rate = playbackRate
        clickState.setPlaybackRate(playbackRate)
        updateClickOutputDelay()
    }

    func setPitchShift(semitones: Float) {
        pitchShiftSemitones = ProjectStateNormalizer.normalizedPitchShift(semitones)
        timePitch.pitch = pitchShiftSemitones * 100
        updateClickOutputDelay()
    }

    func setMainVolume(_ volume: Float) {
        mainVolume = min(1, max(0, volume))
        renderTracks[.original]?.volume = mainVolume
    }

    func applyMix(_ mixState: StemMixState) {
        for type in StemType.allCases {
            renderTracks[.stem(type)]?.volume = mixState.effectiveVolume(for: type)
        }
    }

    func setClickEnabled(_ isEnabled: Bool) {
        isClickEnabled = isEnabled
        clickState.setEnabled(isEnabled)
    }

    func setClickVolume(_ volume: Float) {
        clickVolume = min(1, max(0, volume))
        clickState.setVolume(clickVolume)
    }

    func setClickSettings(_ settings: BeatGridSettings) {
        clickSettings = settings
        clickState.setSettings(settings)
        if let clickTempoMap {
            clickState.setTempoMap(clickTempoMap)
        }
    }

    func setTempoMap(_ tempoMap: TempoMap) {
        clickTempoMap = tempoMap
        clickState.setTempoMap(tempoMap)
    }

    func setClickSoundSettings(_ settings: ClickSoundSettings) {
        clickSoundSettings = settings.clamped()
        clickState.setSoundSettings(clickSoundSettings)
    }

    func resetClickSchedule() {
        clickState.seek(to: transportState.currentFrame)
    }

    func setAudioOutputDevice(uid: String?) throws {
        let normalizedUID = uid?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextUID = normalizedUID?.isEmpty == true ? nil : normalizedUID
        guard nextUID != outputDeviceUID else { return }

        let previousUID = outputDeviceUID
        let wasPlaying = isPlaying
        let preservedTime = currentTime

        outputDeviceUID = nextUID

        do {
            engine.stop()
            try applyOutputDeviceSelection()
            if isLoaded {
                seek(to: preservedTime)
            }
            if wasPlaying {
                try play()
            }
        } catch {
            outputDeviceUID = previousUID
            do {
                try applyOutputDeviceSelection()
                if isLoaded {
                    seek(to: preservedTime)
                }
                if wasPlaying {
                    try play()
                }
            } catch {
                // Preserve the original switching error; recovery failure is not more actionable.
            }
            throw error
        }
    }

    private func loadTracks(_ tracks: [AudioRenderTrack], outputFormat: AVAudioFormat) throws {
        resetEngine()

        guard !tracks.isEmpty else {
            throw MultiTrackAudioPlayerError.noStems
        }

        renderTracks = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        trackOrder = tracks
        self.outputFormat = outputFormat
        durationFrames = tracks.map(\.frameLength).min() ?? 0
        duration = TimeInterval(durationFrames) / outputFormat.sampleRate

        transportState.configure(durationFrames: durationFrames)
        clickState.configure(
            durationFrames: durationFrames,
            sourceSampleRate: outputFormat.sampleRate,
            audioSampleRate: outputFormat.sampleRate
        )
        clickState.setPlaybackRate(playbackRate)
        clickState.setVolume(clickVolume)
        clickState.setSettings(clickSettings)
        if let clickTempoMap {
            clickState.setTempoMap(clickTempoMap)
        }
        clickState.setSoundSettings(clickSoundSettings)
        clickState.setEnabled(isClickEnabled)

        let sourceNode = makeTrackSourceNode(format: outputFormat)
        let clickNode = AVAudioSourceNode(format: outputFormat) { [clickState] _, _, frameCount, outputData in
            clickState.render(frameCount: frameCount, outputData: outputData)
            return noErr
        }

        self.sourceNode = sourceNode
        self.clickNode = clickNode
        timePitch.rate = playbackRate
        timePitch.pitch = pitchShiftSemitones * 100

        engine.attach(sourceNode)
        engine.attach(timePitch)
        engine.attach(clickNode)
        engine.connect(sourceNode, to: timePitch, format: outputFormat)
        engine.connect(timePitch, to: engine.mainMixerNode, format: outputFormat)
        engine.connect(clickNode, to: engine.mainMixerNode, format: outputFormat)
        try applyOutputDeviceSelection()
        engine.prepare()
        updateClickOutputDelay()
        try engine.start()
        applyLoopState()
        isLoaded = true
    }

    private func makeTrackSourceNode(format: AVAudioFormat) -> AVAudioSourceNode {
        let transportState = self.transportState
        let tracks = self.trackOrder
        let channelCount = Int(format.channelCount)

        return AVAudioSourceNode(format: format) { _, _, frameCount, outputData in
            let outputBuffers = UnsafeMutableAudioBufferListPointer(outputData)
            for buffer in outputBuffers {
                memset(buffer.mData, 0, Int(buffer.mDataByteSize))
            }

            for frame in 0..<Int(frameCount) {
                guard let sourceFrame = transportState.nextSourceFrame() else { continue }
                let sourceIndex = Int(sourceFrame)

                for track in tracks {
                    guard
                        sourceIndex < track.frameLength,
                        let inputChannels = track.buffer.floatChannelData
                    else {
                        continue
                    }

                    let gain = track.volume
                    guard gain > 0 else { continue }

                    for channel in 0..<min(channelCount, outputBuffers.count) {
                        guard let output = outputBuffers[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
                        let inputChannel = min(channel, track.channelCount - 1)
                        output[frame] += inputChannels[inputChannel][sourceIndex] * gain
                    }
                }
            }

            return noErr
        }
    }

    private func renderTrack(
        id: TrackID,
        url: URL,
        outputFormat: AVAudioFormat,
        volume: Float
    ) throws -> AudioRenderTrack {
        let file = try AVAudioFile(forReading: url)
        let buffer = try decode(file: file, to: outputFormat)
        return AudioRenderTrack(id: id, buffer: buffer, volume: volume)
    }

    private func decode(file: AVAudioFile, to outputFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = file.processingFormat
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw MultiTrackAudioPlayerError.audioConversionFailed
        }

        try file.read(into: inputBuffer)

        if formatsMatch(inputFormat, outputFormat), inputBuffer.floatChannelData != nil {
            return inputBuffer
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw MultiTrackAudioPlayerError.audioConversionFailed
        }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 1_024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            throw MultiTrackAudioPlayerError.audioConversionFailed
        }

        var didProvideInput = false
        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, status in
            if didProvideInput {
                status.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            status.pointee = .haveData
            return inputBuffer
        }

        if conversionError != nil || outputBuffer.floatChannelData == nil {
            throw MultiTrackAudioPlayerError.audioConversionFailed
        }

        return outputBuffer
    }

    private func renderFormat(for sourceFormat: AVAudioFormat) throws -> AVAudioFormat {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceFormat.sampleRate,
            channels: sourceFormat.channelCount,
            interleaved: false
        ) else {
            throw MultiTrackAudioPlayerError.unsupportedAudioFormat
        }

        return format
    }

    private func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.commonFormat == rhs.commonFormat &&
            lhs.sampleRate == rhs.sampleRate &&
            lhs.channelCount == rhs.channelCount &&
            lhs.isInterleaved == rhs.isInterleaved
    }

    private func applyLoopState() {
        guard let outputFormat else { return }

        let loop = loopRegion.clamped(to: duration)
        let startFrame = frame(for: loop.start, sampleRate: outputFormat.sampleRate)
        let endFrame = frame(for: loop.end, sampleRate: outputFormat.sampleRate)
        transportState.setLoop(enabled: isLoopEnabled, startFrame: startFrame, endFrame: endFrame)
        clickState.setLoop(enabled: isLoopEnabled, startFrame: startFrame, endFrame: endFrame)
    }

    private func updateClickOutputDelay() {
        clickState.setOutputDelay(seconds: timePitch.latency)
    }

    private func applyOutputDeviceSelection() throws {
        let deviceID: AudioDeviceID
        if let outputDeviceUID {
            deviceID = try audioDeviceService.deviceID(forUID: outputDeviceUID, kind: .output)
        } else {
            deviceID = try audioDeviceService.defaultDeviceID(kind: .output)
        }

        guard let audioUnit = engine.outputNode.audioUnit else {
            throw MultiTrackAudioPlayerError.outputDeviceUnavailable
        }

        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw AudioDeviceServiceError.deviceSwitchFailed(status)
        }
    }

    private func frame(for time: TimeInterval, sampleRate: Double) -> AVAudioFramePosition {
        let requestedFrame = AVAudioFramePosition((max(0, time) * sampleRate).rounded())
        return min(durationFrames, max(0, requestedFrame))
    }

    private func resetEngine() {
        sourceNode = nil
        clickNode = nil
        engine.stop()

        engine = AVAudioEngine()
        timePitch = AVAudioUnitTimePitch()
        renderTracks = [:]
        trackOrder = []
        outputFormat = nil
        duration = 0
        durationFrames = 0
        transportState.configure(durationFrames: 0)
        clickState.configure(durationFrames: 0, sourceSampleRate: 44_100, audioSampleRate: 44_100)
        isLoaded = false
        isPlaying = false
    }
}
