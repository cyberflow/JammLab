import Foundation

struct ProjectStateNormalizer {
    static func normalizedDuration(_ duration: TimeInterval) -> TimeInterval {
        duration.isFinite ? max(0, duration) : 0
    }

    static func normalizedTempo(_ bpm: Double?) -> Double? {
        guard let bpm, bpm.isFinite else { return nil }
        return max(0.1, min(999.9, (bpm * 10).rounded() / 10))
    }

    static func normalizedPlaybackRate(_ rate: Float) -> Float {
        guard rate.isFinite else { return 1 }
        return min(1, max(0.25, rate))
    }

    static func normalizedPitchShift(_ semitones: Float) -> Float {
        guard semitones.isFinite else { return 0 }
        return min(12, max(-12, semitones))
    }

    static func normalizedBeatGridSettings(
        projectSettings: BeatGridSettings?,
        legacyTempoBPM: Double?,
        duration: TimeInterval
    ) -> BeatGridSettings {
        var settings = (projectSettings ?? BeatGridSettings(bpm: legacyTempoBPM)).clamped(to: duration)
        settings.bpm = normalizedTempo(settings.bpm)
        return settings
    }

    static func normalizedLoopRegion(
        start: TimeInterval,
        end: TimeInterval,
        duration: TimeInterval,
        minimumLength: TimeInterval = LoopRegion.minimumLength
    ) -> LoopRegion {
        LoopRegion(
            start: finiteTime(start),
            end: finiteTime(end)
        )
        .clamped(to: duration, minimumLength: minimumLength)
    }

    static func normalizedNotes(_ notes: [TimecodedNote], duration: TimeInterval) -> [TimecodedNote] {
        notes
            .map { normalizedNote($0, duration: duration) }
            .sorted { $0.time < $1.time }
    }

    static func normalizedNote(_ note: TimecodedNote, duration: TimeInterval) -> TimecodedNote {
        let title = normalizedTitle(note.title, fallback: note.isRegion ? "Region" : "Marker")

        guard note.isRegion else {
            return TimecodedNote(
                id: note.id,
                kind: .marker,
                time: max(0, min(finiteTime(note.time), duration)),
                title: title,
                color: note.color,
                customColorHex: note.normalizedCustomColorHex,
                comment: note.comment,
                metadata: note.metadata
            )
        }

        let range = LoopRegion(
            start: finiteTime(note.time),
            end: finiteTime(note.regionEndTime)
        )
        .clamped(to: duration)

        return TimecodedNote(
            id: note.id,
            kind: .region,
            time: range.start,
            duration: range.duration,
            title: title,
            color: note.color,
            customColorHex: note.normalizedCustomColorHex,
            comment: note.comment,
            metadata: note.metadata
        )
    }

    private static func finiteTime(_ time: TimeInterval) -> TimeInterval {
        time.isFinite ? time : 0
    }

    private static func normalizedTitle(_ title: String, fallback: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? fallback : trimmedTitle
    }
}
