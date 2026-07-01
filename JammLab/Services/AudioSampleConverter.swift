import AVFoundation

enum AudioSampleConverter {
    static func monoFloatSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return [] }
        guard buffer.format.commonFormat == .pcmFormatFloat32 else { return nil }

        if buffer.format.isInterleaved {
            return interleavedMonoFloatSamples(from: buffer, frameLength: frameLength, channelCount: channelCount)
        }

        return nonInterleavedMonoFloatSamples(from: buffer, frameLength: frameLength, channelCount: channelCount)
    }

    private static func nonInterleavedMonoFloatSamples(
        from buffer: AVAudioPCMBuffer,
        frameLength: Int,
        channelCount: Int
    ) -> [Float]? {
        guard let channels = buffer.floatChannelData else { return nil }

        var mono = Array(repeating: Float(0), count: frameLength)
        for channel in 0..<channelCount {
            let data = channels[channel]
            for index in 0..<frameLength {
                mono[index] += data[index] / Float(channelCount)
            }
        }

        return mono
    }

    private static func interleavedMonoFloatSamples(
        from buffer: AVAudioPCMBuffer,
        frameLength: Int,
        channelCount: Int
    ) -> [Float]? {
        let audioBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard let audioBuffer = audioBuffers.first,
              let data = audioBuffer.mData else {
            return nil
        }

        let sampleCount = frameLength * channelCount
        let interleaved = data.bindMemory(to: Float.self, capacity: sampleCount)
        var mono = Array(repeating: Float(0), count: frameLength)
        for frame in 0..<frameLength {
            let frameOffset = frame * channelCount
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += interleaved[frameOffset + channel]
            }
            mono[frame] = sum / Float(channelCount)
        }

        return mono
    }
}
