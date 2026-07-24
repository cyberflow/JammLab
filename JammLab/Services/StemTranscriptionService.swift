import AudioToolbox
import Foundation

enum StemTranscriptionError: LocalizedError, Equatable {
    case stemAudioUnavailable
    case unsupportedAudioFormat
    case audioDecodingFailed
    case resamplingFailed
    case modelResourceMissing
    case modelInitializationFailed
    case inferenceFailed
    case invalidModelOutput
    case cancelled
    case sourceStemChanged
    case resultCouldNotBeAdded

    var errorDescription: String? {
        switch self {
        case .stemAudioUnavailable:
            return "The selected stem audio is unavailable."
        case .unsupportedAudioFormat:
            return "The selected stem uses an unsupported audio format."
        case .audioDecodingFailed:
            return "JammLab could not decode the selected stem."
        case .resamplingFailed:
            return "JammLab could not prepare the stem for transcription."
        case .modelResourceMissing:
            return "The built-in Basic Pitch model is missing."
        case .modelInitializationFailed:
            return "The built-in transcription model could not be initialized."
        case .inferenceFailed:
            return "The selected stem could not be transcribed."
        case .invalidModelOutput:
            return "The transcription model returned an invalid result."
        case .cancelled:
            return "Transcription was cancelled."
        case .sourceStemChanged:
            return "The source stem changed while it was being transcribed."
        case .resultCouldNotBeAdded:
            return "The transcription result could not be added to the project."
        }
    }
}

struct RawStemTranscriptionNote: Equatable {
    var midiPitch: Int
    var startTimeSeconds: TimeInterval
    var endTimeSeconds: TimeInterval
    var confidence: Double
    var pitchBends: [Int]
}

struct RawStemTranscriptionResult: Equatable {
    var notes: [RawStemTranscriptionNote]
    var timings: StemTranscriptionTimings
    var warnings: [String]
}

struct PreparedTranscriptionAudio {
    var url: URL
    var temporaryDirectory: URL
    var sampleCount: Int
    var preparationDuration: Double

    func cleanup(fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: temporaryDirectory)
    }
}

final class StemTranscriptionOperation: @unchecked Sendable {
    fileprivate let nativeToken = JMTranscriptionCancellationToken()
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
        nativeToken.cancel()
    }
}

protocol StemTranscribing: Sendable {
    func transcribe(
        stemURL: URL,
        configuration: StemTranscriptionConfiguration,
        operation: StemTranscriptionOperation,
        progress: @escaping @Sendable (StemTranscriptionPhase, Double) -> Void
    ) async throws -> RawStemTranscriptionResult
}

final class StemTranscriptionService: StemTranscribing, @unchecked Sendable {
    static let modelSampleRate = 22_050.0
    private let bridge = JMBasicPitchBridge()

    func transcribe(
        stemURL: URL,
        configuration: StemTranscriptionConfiguration,
        operation: StemTranscriptionOperation,
        progress: @escaping @Sendable (StemTranscriptionPhase, Double) -> Void
    ) async throws -> RawStemTranscriptionResult {
        try await Task.detached(priority: .userInitiated) {
            let totalStart = ContinuousClock.now
            progress(.preparingAudio, 0)
            let prepared = try self.prepareAudio(
                at: stemURL,
                operation: operation,
                progress: { progress(.preparingAudio, min(1, max(0, $0))) }
            )
            defer { prepared.cleanup() }

            guard !operation.isCancelled else { throw StemTranscriptionError.cancelled }
            progress(.loadingModel, 0)

            let nativeConfiguration = JMTranscriptionConfiguration()
            nativeConfiguration.minimumNoteDurationMilliseconds =
                Float(configuration.minimumNoteDurationMilliseconds)
            nativeConfiguration.noteSensitivity = Float(configuration.noteSensitivity)
            nativeConfiguration.splitSensitivity = Float(configuration.splitSensitivity)
            nativeConfiguration.includePitchBends = configuration.includePitchBends
            nativeConfiguration.windowDurationSeconds = 30
            nativeConfiguration.overlapDurationSeconds = 2

            let result: JMTranscriptionResult
            do {
                result = try self.bridge.transcribePCMFile(
                    at: prepared.url,
                    sampleCount: UInt(prepared.sampleCount),
                    sampleRate: Self.modelSampleRate,
                    configuration: nativeConfiguration,
                    cancellationToken: operation.nativeToken,
                    progress: { progress(.transcribing, $0) }
                )
            } catch {
                throw self.mapBridgeError(error as NSError, cancelled: operation.isCancelled)
            }
            guard !operation.isCancelled else { throw StemTranscriptionError.cancelled }
            progress(.processingNotes, 0)

            let notes = result.notes.compactMap { note -> RawStemTranscriptionNote? in
                guard (0...127).contains(note.pitch),
                      note.startTimeSeconds.isFinite,
                      note.endTimeSeconds.isFinite,
                      note.endTimeSeconds > note.startTimeSeconds,
                      note.confidence.isFinite
                else { return nil }
                return RawStemTranscriptionNote(
                    midiPitch: note.pitch,
                    startTimeSeconds: note.startTimeSeconds,
                    endTimeSeconds: note.endTimeSeconds,
                    confidence: note.confidence,
                    pitchBends: note.pitchBends.map(\.intValue)
                )
            }
            guard notes.count == result.notes.count else {
                throw StemTranscriptionError.invalidModelOutput
            }

            let elapsed = totalStart.duration(to: .now)
            let totalSeconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
            progress(.processingNotes, 1)
            return RawStemTranscriptionResult(
                notes: notes,
                timings: StemTranscriptionTimings(
                    audioPreparationSeconds: prepared.preparationDuration,
                    modelLoadSeconds: result.timings.modelLoadSeconds,
                    inferenceSeconds: result.timings.inferenceSeconds,
                    postProcessingSeconds: result.timings.postProcessingSeconds,
                    totalSeconds: totalSeconds,
                    processedDurationSeconds: result.processedDurationSeconds
                ),
                warnings: result.warnings
            )
        }.value
    }

    func prepareAudio(
        at sourceURL: URL,
        operation: StemTranscriptionOperation,
        progress: @escaping (Double) -> Void
    ) throws -> PreparedTranscriptionAudio {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw StemTranscriptionError.stemAudioUnavailable
        }

        let start = ContinuousClock.now
        var audioFile: ExtAudioFileRef?
        let openStatus = ExtAudioFileOpenURL(sourceURL as CFURL, &audioFile)
        guard openStatus == noErr, let audioFile else {
            throw StemTranscriptionError.unsupportedAudioFormat
        }
        defer { ExtAudioFileDispose(audioFile) }

        var sourceFormat = AudioStreamBasicDescription()
        var sourceFormatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let formatStatus = ExtAudioFileGetProperty(
            audioFile,
            kExtAudioFileProperty_FileDataFormat,
            &sourceFormatSize,
            &sourceFormat
        )
        guard formatStatus == noErr,
              sourceFormat.mSampleRate.isFinite,
              sourceFormat.mSampleRate > 0
        else {
            throw StemTranscriptionError.unsupportedAudioFormat
        }

        var sourceLengthFrames: Int64 = 0
        var propertySize = UInt32(MemoryLayout<Int64>.size)
        let lengthStatus = ExtAudioFileGetProperty(
            audioFile,
            kExtAudioFileProperty_FileLengthFrames,
            &propertySize,
            &sourceLengthFrames
        )
        guard lengthStatus == noErr else { throw StemTranscriptionError.audioDecodingFailed }
        let expectedOutputFrames = Double(sourceLengthFrames)
            * Self.modelSampleRate
            / sourceFormat.mSampleRate

        let sourceChannelCount = max(1, Int(sourceFormat.mChannelsPerFrame))
        let bytesPerFrame = UInt32(MemoryLayout<Float>.size * sourceChannelCount)
        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: Self.modelSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian,
            mBytesPerPacket: bytesPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: UInt32(sourceChannelCount),
            mBitsPerChannel: 32,
            mReserved: 0
        )
        let clientStatus = ExtAudioFileSetProperty(
            audioFile,
            kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &clientFormat
        )
        guard clientStatus == noErr else { throw StemTranscriptionError.resamplingFailed }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JammLabTranscription-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        let outputURL = temporaryDirectory.appendingPathComponent("mono-22050.f32")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        guard let output = try? FileHandle(forWritingTo: outputURL) else {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw StemTranscriptionError.resamplingFailed
        }
        defer { try? output.close() }

        let chunkCapacity: UInt32 = 32_768
        var interleavedSamples = Array(
            repeating: Float.zero,
            count: Int(chunkCapacity) * sourceChannelCount
        )
        var monoSamples = Array(repeating: Float.zero, count: Int(chunkCapacity))
        var sampleCount = 0
        do {
            while true {
                guard !operation.isCancelled else { throw StemTranscriptionError.cancelled }
                var frameCount = chunkCapacity
                let readStatus = interleavedSamples.withUnsafeMutableBytes { bytes -> OSStatus in
                    let buffer = AudioBuffer(
                        mNumberChannels: UInt32(sourceChannelCount),
                        mDataByteSize: chunkCapacity * bytesPerFrame,
                        mData: bytes.baseAddress
                    )
                    var bufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: buffer)
                    return ExtAudioFileRead(audioFile, &frameCount, &bufferList)
                }
                guard readStatus == noErr else { throw StemTranscriptionError.audioDecodingFailed }
                guard frameCount > 0 else { break }

                for frameIndex in 0..<Int(frameCount) {
                    let sourceOffset = frameIndex * sourceChannelCount
                    var sum = 0.0
                    for channelIndex in 0..<sourceChannelCount {
                        sum += Double(interleavedSamples[sourceOffset + channelIndex])
                    }
                    monoSamples[frameIndex] = Float(sum / Double(sourceChannelCount))
                }
                try monoSamples.withUnsafeBytes { bytes in
                    let count = Int(frameCount) * MemoryLayout<Float>.size
                    try output.write(contentsOf: Data(bytes: bytes.baseAddress!, count: count))
                }
                sampleCount += Int(frameCount)
                if expectedOutputFrames > 0 {
                    progress(min(0.99, Double(sampleCount) / expectedOutputFrames))
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw error
        }

        guard sampleCount > 0 else {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw StemTranscriptionError.audioDecodingFailed
        }
        progress(1)
        let elapsed = start.duration(to: .now)
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        return PreparedTranscriptionAudio(
            url: outputURL,
            temporaryDirectory: temporaryDirectory,
            sampleCount: sampleCount,
            preparationDuration: seconds
        )
    }

    private func mapBridgeError(_ error: NSError?, cancelled: Bool) -> StemTranscriptionError {
        if cancelled {
            return .cancelled
        }
        guard error?.domain == JMTranscriptionErrorDomain else {
            return .inferenceFailed
        }
        if error?.code == 8 {
            return .cancelled
        }
        switch error?.code {
        case 1:
            return .audioDecodingFailed
        case 2:
            return .resamplingFailed
        case 3:
            return .audioDecodingFailed
        case 4:
            return .modelResourceMissing
        case 5:
            return .modelInitializationFailed
        case 7:
            return .invalidModelOutput
        default:
            return .inferenceFailed
        }
    }
}
