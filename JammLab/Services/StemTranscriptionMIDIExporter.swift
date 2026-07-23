import Foundation

enum StemTranscriptionMIDIExporter {
    static func data(
        for track: StemTranscriptionTrack,
        ticksPerQuarter: UInt16 = 480,
        tempoBPM: Double
    ) -> Data {
        let secondsPerQuarter = 60.0 / max(1, tempoBPM)
        let noteEvents = track.notes.flatMap { note -> [(tick: UInt32, bytes: [UInt8])] in
            let startTick = UInt32(max(0, (note.projectStartTimeSeconds / secondsPerQuarter
                * Double(ticksPerQuarter)).rounded()))
            let endTick = UInt32(max(
                Double(startTick + 1),
                (note.projectEndTimeSeconds / secondsPerQuarter * Double(ticksPerQuarter)).rounded()
            ))
            let pitch = UInt8(clamping: note.midiPitch)
            let velocity = UInt8(clamping: Int((max(0, min(1, note.confidence)) * 127).rounded()))
            return [
                (startTick, [0x90, pitch, max(1, velocity)]),
                (endTick, [0x80, pitch, 0])
            ]
        }.sorted {
            if $0.tick != $1.tick { return $0.tick < $1.tick }
            return $0.bytes[0] < $1.bytes[0]
        }

        var trackBytes: [UInt8] = []
        let microsecondsPerQuarter = UInt32((60_000_000 / max(1, tempoBPM)).rounded())
        trackBytes += [0x00, 0xFF, 0x51, 0x03]
        trackBytes += [
            UInt8((microsecondsPerQuarter >> 16) & 0xFF),
            UInt8((microsecondsPerQuarter >> 8) & 0xFF),
            UInt8(microsecondsPerQuarter & 0xFF)
        ]

        var previousTick: UInt32 = 0
        for event in noteEvents {
            trackBytes += variableLength(event.tick - previousTick)
            trackBytes += event.bytes
            previousTick = event.tick
        }
        trackBytes += [0x00, 0xFF, 0x2F, 0x00]

        var data = Data("MThd".utf8)
        data.append(contentsOf: [0, 0, 0, 6, 0, 0, 0, 1])
        data.append(contentsOf: [
            UInt8((ticksPerQuarter >> 8) & 0xFF),
            UInt8(ticksPerQuarter & 0xFF)
        ])
        data.append(Data("MTrk".utf8))
        let length = UInt32(trackBytes.count)
        data.append(contentsOf: [
            UInt8((length >> 24) & 0xFF),
            UInt8((length >> 16) & 0xFF),
            UInt8((length >> 8) & 0xFF),
            UInt8(length & 0xFF)
        ])
        data.append(contentsOf: trackBytes)
        return data
    }

    private static func variableLength(_ value: UInt32) -> [UInt8] {
        var value = value
        var buffer = [UInt8(value & 0x7F)]
        while value > 0x7F {
            value >>= 7
            buffer.insert(UInt8(value & 0x7F) | 0x80, at: 0)
        }
        return buffer
    }
}
