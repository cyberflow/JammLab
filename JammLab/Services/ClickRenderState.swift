@preconcurrency import AVFoundation
import Foundation

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

final class ClickRenderState {
    private var settings = BeatGridSettings()
    private var tempoSegments: [TempoMapSegment] = []
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
        rebuildSingleSegmentTempoMap()
        updateDelayFrames()
        recalculateNextBeat()
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = Double(ProjectStateNormalizer.normalizedPlaybackRate(rate))
    }

    func setSettings(_ settings: BeatGridSettings) {
        self.settings = settings
        rebuildSingleSegmentTempoMap()
        recalculateNextBeat()
    }

    func setTempoMap(_ tempoMap: TempoMap) {
        tempoSegments = tempoMap.segments
        settings = tempoMap.settings(at: max(0, min(durationSeconds, sourceFrame / max(sourceSampleRate, 1))))
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
            let beatSettings = settings(forFrame: beatFrame)
            let beatIndex = beatIndex(for: beatFrame, settings: beatSettings)
            let isAccent = beatIndex % max(1, beatSettings.timeSignature.beatsPerBar) == 0
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
        guard isEnabled, sourceSampleRate > 0 else { return nil }

        let segments = tempoSegments.isEmpty ? singleSegmentTempoMap() : tempoSegments
        for segment in segments {
            let segmentStartFrame = segment.startTime * sourceSampleRate
            let segmentEndFrame = min(segment.endTime * sourceSampleRate, durationFrames)
            guard segmentEndFrame > frame - 0.5 else { continue }
            guard let candidate = nextBeatFrame(
                after: max(frame, segmentStartFrame),
                settings: segment.settings,
                segmentStartFrame: segmentStartFrame,
                segmentEndFrame: segmentEndFrame
            ) else {
                continue
            }
            return candidate
        }

        return nil
    }

    private func nextBeatFrame(
        after frame: Double,
        settings: BeatGridSettings,
        segmentStartFrame: Double,
        segmentEndFrame: Double
    ) -> Double? {
        guard let bpm = settings.bpm, bpm > 0, sourceSampleRate > 0 else { return nil }

        let framesPerBeat = sourceSampleRate * 60 / bpm
        guard framesPerBeat > 0 else { return nil }

        let firstBeatFrame = settings.firstBeatTime * sourceSampleRate
        var beatIndex = Int(ceil((frame - firstBeatFrame) / framesPerBeat - 0.000_001))
        var candidate = firstBeatFrame + Double(beatIndex) * framesPerBeat
        while candidate < max(0, segmentStartFrame) - 0.5 {
            beatIndex += 1
            candidate = firstBeatFrame + Double(beatIndex) * framesPerBeat
        }
        while candidate < frame - 0.5 {
            beatIndex += 1
            candidate = firstBeatFrame + Double(beatIndex) * framesPerBeat
        }
        guard candidate < min(segmentEndFrame, durationFrames) else { return nil }
        return candidate
    }

    private func beatIndex(for frame: Double, settings: BeatGridSettings) -> Int {
        guard let bpm = settings.bpm, bpm > 0 else { return 0 }
        let framesPerBeat = sourceSampleRate * 60 / bpm
        guard framesPerBeat > 0 else { return 0 }
        let firstBeatFrame = settings.firstBeatTime * sourceSampleRate
        return Int(round((frame - firstBeatFrame) / framesPerBeat))
    }

    private func settings(forFrame frame: Double) -> BeatGridSettings {
        let time = max(0, min(durationSeconds, frame / max(sourceSampleRate, 1)))
        return (tempoSegments.isEmpty ? singleSegmentTempoMap() : tempoSegments)
            .last(where: { $0.startTime <= time && time < $0.endTime })?
            .settings
            ?? settings
    }

    private var durationSeconds: TimeInterval {
        guard sourceSampleRate > 0 else { return 0 }
        return durationFrames / sourceSampleRate
    }

    private func rebuildSingleSegmentTempoMap() {
        tempoSegments = singleSegmentTempoMap()
    }

    private func singleSegmentTempoMap() -> [TempoMapSegment] {
        [TempoMapSegment(startTime: 0, endTime: durationSeconds, settings: settings)]
    }

    private func updateDelayFrames() {
        let frames = Int((outputDelaySeconds * audioSampleRate).rounded())
        delayLine.setDelayFrames(frames)
    }
}
