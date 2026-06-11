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

private final class AudioRenderTrack {
    let id: MultiTrackAudioPlayer.TrackID
    let buffer: AVAudioPCMBuffer
    let frameLength: AVAudioFramePosition
    let channelCount: Int
    var volume: Float

    init(id: MultiTrackAudioPlayer.TrackID, buffer: AVAudioPCMBuffer, volume: Float) {
        self.id = id
        self.buffer = buffer
        self.frameLength = AVAudioFramePosition(buffer.frameLength)
        self.channelCount = Int(buffer.format.channelCount)
        self.volume = volume
    }
}

private final class AudioTransportRenderState {
    private(set) var sourceFrame: Double = 0
    private var durationFrames: Double = 0
    private var loopStartFrame: Double = 0
    private var loopEndFrame: Double = 0
    private var isLoopEnabled = false
    private var loopArmed = false
    private var isPlaying = false
    private var didReachEnd = false

    var currentFrame: AVAudioFramePosition {
        AVAudioFramePosition(max(0, min(durationFrames, sourceFrame)).rounded())
    }

    var reachedEnd: Bool {
        didReachEnd
    }

    func configure(durationFrames: AVAudioFramePosition) {
        self.durationFrames = max(0, Double(durationFrames))
        sourceFrame = min(sourceFrame, self.durationFrames)
        loopStartFrame = 0
        loopEndFrame = self.durationFrames
        loopArmed = false
        didReachEnd = false
    }

    func setLoop(enabled: Bool, startFrame: AVAudioFramePosition, endFrame: AVAudioFramePosition) {
        let start = max(0, min(Double(startFrame), durationFrames))
        let end = max(0, min(Double(endFrame), durationFrames))
        isLoopEnabled = enabled && end > start
        loopStartFrame = start
        loopEndFrame = end
        if !isLoopEnabled {
            loopArmed = false
        } else if sourceFrame < loopEndFrame {
            loopArmed = true
        } else {
            loopArmed = false
        }
    }

    func play() {
        if sourceFrame >= durationFrames {
            sourceFrame = 0
        }
        didReachEnd = false
        loopArmed = isLoopEnabled && sourceFrame < loopEndFrame
        isPlaying = true
    }

    func pause() {
        isPlaying = false
    }

    func stop() {
        sourceFrame = 0
        isPlaying = false
        didReachEnd = false
        loopArmed = isLoopEnabled && sourceFrame < loopEndFrame
    }

    func seek(to frame: AVAudioFramePosition) {
        sourceFrame = max(0, min(durationFrames, Double(frame)))
        didReachEnd = false
        loopArmed = isLoopEnabled && sourceFrame < loopEndFrame
    }

    func nextSourceFrame() -> AVAudioFramePosition? {
        guard isPlaying, !didReachEnd else { return nil }

        if sourceFrame >= durationFrames {
            didReachEnd = true
            isPlaying = false
            return nil
        }

        if isLoopEnabled, loopArmed, sourceFrame >= loopEndFrame {
            sourceFrame = loopStartFrame
        }

        let frame = AVAudioFramePosition(max(0, min(durationFrames - 1, sourceFrame)))
        sourceFrame += 1

        if isLoopEnabled, loopArmed, sourceFrame >= loopEndFrame {
            sourceFrame = loopStartFrame
        } else if sourceFrame >= durationFrames {
            didReachEnd = true
            isPlaying = false
        }

        return frame
    }
}

struct ClickDelayLine {
    private(set) var delayFrames = 0
    private var buffer: [Float] = []
    private var index = 0

    mutating func setDelayFrames(_ frames: Int) {
        let clampedFrames = max(0, frames)
        guard clampedFrames != delayFrames else { return }

        delayFrames = clampedFrames
        buffer = Array(repeating: 0, count: clampedFrames)
        index = 0
    }

    mutating func process(_ sample: Float) -> Float {
        guard delayFrames > 0 else { return sample }

        let delayedSample = buffer[index]
        buffer[index] = sample
        index = (index + 1) % delayFrames
        return delayedSample
    }
}

private final class ClickRenderState {
    private var settings = BeatGridSettings()
    private var soundSettings = ClickSoundSettings.defaultValue
    private var isEnabled = false
    private var volume: Float = 0.65
    private var sourceFrame: Double = 0
    private var durationFrames: Double = 0
    private var loopStartFrame: Double = 0
    private var loopEndFrame: Double = 0
    private var isLoopEnabled = false
    private var loopArmed = false
    private var isPlaying = false
    private var audioSampleRate: Double = 44_100
    private var sourceSampleRate: Double = 44_100
    private var playbackRate: Double = 1
    private var nextBeatFrame: Double?
    private var activeClickFrame = 0
    private var activeClickLength = 0
    private var activeFrequency = 1_120.0
    private var activeGain: Float = 0.62
    private var outputDelaySeconds: TimeInterval = 0
    private var delayLine = ClickDelayLine()

    func configure(durationFrames: AVAudioFramePosition, sourceSampleRate: Double, audioSampleRate: Double) {
        self.durationFrames = max(0, Double(durationFrames))
        self.sourceSampleRate = sourceSampleRate
        self.audioSampleRate = audioSampleRate
        sourceFrame = min(sourceFrame, self.durationFrames)
        updateDelayFrames()
        recalculateNextBeat()
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = Double(min(1, max(0.25, rate)))
    }

    func setSettings(_ settings: BeatGridSettings) {
        self.settings = settings
        recalculateNextBeat()
    }

    func setSoundSettings(_ settings: ClickSoundSettings) {
        soundSettings = settings.clamped()
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        recalculateNextBeat()
    }

    func setVolume(_ volume: Float) {
        self.volume = min(1, max(0, volume))
    }

    func setOutputDelay(seconds: TimeInterval) {
        outputDelaySeconds = max(0, seconds)
        updateDelayFrames()
    }

    func setLoop(enabled: Bool, startFrame: AVAudioFramePosition, endFrame: AVAudioFramePosition) {
        let start = max(0, min(Double(startFrame), durationFrames))
        let end = max(0, min(Double(endFrame), durationFrames))
        isLoopEnabled = enabled && end > start
        loopStartFrame = start
        loopEndFrame = end
        if !isLoopEnabled {
            loopArmed = false
        } else if sourceFrame < loopEndFrame {
            loopArmed = true
        } else {
            loopArmed = false
        }
        recalculateNextBeat()
    }

    func play(startFrame: AVAudioFramePosition) {
        sourceFrame = max(0, min(durationFrames, Double(startFrame)))
        if sourceFrame >= durationFrames {
            sourceFrame = 0
        }
        loopArmed = isLoopEnabled && sourceFrame < loopEndFrame
        isPlaying = true
        activeClickFrame = 0
        activeClickLength = 0
        recalculateNextBeat()
    }

    func pause(at frame: AVAudioFramePosition) {
        sourceFrame = max(0, min(durationFrames, Double(frame)))
        isPlaying = false
        recalculateNextBeat()
    }

    func stop() {
        sourceFrame = 0
        isPlaying = false
        activeClickFrame = 0
        activeClickLength = 0
        recalculateNextBeat()
    }

    func seek(to frame: AVAudioFramePosition) {
        sourceFrame = max(0, min(durationFrames, Double(frame)))
        loopArmed = isLoopEnabled && sourceFrame < loopEndFrame
        activeClickFrame = 0
        activeClickLength = 0
        recalculateNextBeat()
    }

    func render(frameCount: AVAudioFrameCount, outputData: UnsafeMutablePointer<AudioBufferList>) {
        let outputBuffers = UnsafeMutableAudioBufferListPointer(outputData)
        for buffer in outputBuffers {
            memset(buffer.mData, 0, Int(buffer.mDataByteSize))
        }

        let count = Int(frameCount)

        for frame in 0..<count {
            if isPlaying, isEnabled {
                triggerBeatIfNeeded()
            }

            let sample = delayLine.process(activeClickSample())
            for buffer in outputBuffers {
                guard let output = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                output[frame] = sample
            }
            advanceSourceFrame()
        }
    }

    private func triggerBeatIfNeeded() {
        guard let beatFrame = nextBeatFrame else { return }

        if sourceFrame + 0.5 >= beatFrame {
            let beatIndex = beatIndex(for: beatFrame)
            let isAccent = beatIndex % max(1, settings.timeSignature.beatsPerBar) == 0
            activeFrequency = isAccent ? soundSettings.accentFrequencyHz : soundSettings.regularFrequencyHz
            activeGain = isAccent ? 0.95 : 0.62
            activeClickFrame = 0
            let lengthMs = isAccent ? soundSettings.accentLengthMs : soundSettings.regularLengthMs
            activeClickLength = max(1, Int(audioSampleRate * lengthMs / 1_000))
            nextBeatFrame = nextBeatFrame(after: beatFrame + 0.5)
        }
    }

    private func activeClickSample() -> Float {
        guard activeClickFrame < activeClickLength, activeClickLength > 0 else { return 0 }

        let time = Double(activeClickFrame) / audioSampleRate
        let progress = Double(activeClickFrame) / Double(activeClickLength)
        let envelope = pow(max(0, 1 - progress), 4.2)
        let transient = activeClickFrame < 4 ? 1.0 - Double(activeClickFrame) * 0.18 : 0
        let tone = sin(2 * .pi * activeFrequency * time)
        let partial = sin(2 * .pi * activeFrequency * 2.01 * time) * 0.22
        activeClickFrame += 1
        return Float((tone + partial + transient) * envelope) * activeGain * volume
    }

    private func advanceSourceFrame() {
        guard isPlaying else { return }

        sourceFrame += playbackRate * sourceSampleRate / audioSampleRate

        if isLoopEnabled, loopArmed, sourceFrame >= loopEndFrame {
            sourceFrame = loopStartFrame + (sourceFrame - loopEndFrame)
            recalculateNextBeat()
        } else if sourceFrame >= durationFrames {
            isPlaying = false
        }
    }

    private func recalculateNextBeat() {
        nextBeatFrame = nextBeatFrame(after: sourceFrame)
    }

    private func nextBeatFrame(after frame: Double) -> Double? {
        guard isEnabled, let bpm = settings.bpm, bpm > 0, sourceSampleRate > 0 else { return nil }

        let framesPerBeat = sourceSampleRate * 60 / bpm
        guard framesPerBeat > 0 else { return nil }

        let firstBeatFrame = settings.firstBeatTime * sourceSampleRate
        var beatIndex = Int(ceil((frame - firstBeatFrame) / framesPerBeat - 0.000_001))
        var candidate = firstBeatFrame + Double(beatIndex) * framesPerBeat
        while candidate < 0 {
            beatIndex += 1
            candidate = firstBeatFrame + Double(beatIndex) * framesPerBeat
        }
        while candidate < frame - 0.5 {
            beatIndex += 1
            candidate = firstBeatFrame + Double(beatIndex) * framesPerBeat
        }
        guard candidate < durationFrames else { return nil }
        return candidate
    }

    private func beatIndex(for frame: Double) -> Int {
        guard let bpm = settings.bpm, bpm > 0 else { return 0 }
        let framesPerBeat = sourceSampleRate * 60 / bpm
        guard framesPerBeat > 0 else { return 0 }
        let firstBeatFrame = settings.firstBeatTime * sourceSampleRate
        return Int(round((frame - firstBeatFrame) / framesPerBeat))
    }

    private func updateDelayFrames() {
        let frames = Int((outputDelaySeconds * audioSampleRate).rounded())
        delayLine.setDelayFrames(frames)
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
        playbackRate = min(1, max(0.25, rate))
        timePitch.rate = playbackRate
        clickState.setPlaybackRate(playbackRate)
        updateClickOutputDelay()
    }

    func setPitchShift(semitones: Float) {
        pitchShiftSemitones = min(12, max(-12, semitones))
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
