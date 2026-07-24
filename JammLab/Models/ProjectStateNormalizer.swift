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
        guard rate.isFinite else { return AppSliderDefaults.playbackRate }
        return min(AppSliderDefaults.maximumPlaybackRate, max(AppSliderDefaults.minimumPlaybackRate, rate))
    }

    static func normalizedPitchShift(_ semitones: Float) -> Float {
        guard semitones.isFinite else { return AppSliderDefaults.pitchShiftSemitones }
        return min(
            AppSliderDefaults.maximumPitchShiftSemitones,
            max(AppSliderDefaults.minimumPitchShiftSemitones, semitones)
        )
    }

    static func normalizedTimelineTime(_ time: TimeInterval?, duration: TimeInterval) -> TimeInterval {
        guard let time else { return 0 }
        return max(0, min(finiteTime(time), normalizedDuration(duration)))
    }

    static func normalizedTimelineVisibleRange(
        _ range: ProjectTimelineVisibleRange?,
        duration: TimeInterval
    ) -> ClosedRange<TimeInterval> {
        let duration = normalizedDuration(duration)
        guard duration > 0 else { return 0...0 }
        guard
            let range,
            range.start.isFinite,
            range.end.isFinite,
            range.start >= 0,
            range.end <= duration,
            range.end > range.start
        else {
            return 0...duration
        }

        return range.start...range.end
    }

    static func normalizedTimelineVisibleRange(
        _ range: ClosedRange<TimeInterval>,
        duration: TimeInterval
    ) -> ClosedRange<TimeInterval> {
        let duration = normalizedDuration(duration)
        guard duration > 0 else { return 0...0 }
        guard range.lowerBound.isFinite, range.upperBound.isFinite else { return 0...duration }

        let normalizedRange = TimelineViewport(duration: duration, visibleRange: range).clampedRange
        guard normalizedRange.upperBound > normalizedRange.lowerBound else { return 0...duration }
        return normalizedRange
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

    static func normalizedHarmonySymbols(
        _ symbols: [HarmonySymbol],
        duration: TimeInterval
    ) -> [HarmonySymbol] {
        let duration = normalizedDuration(duration)
        return symbols
            .map { symbol in
                HarmonySymbol(
                    id: symbol.id,
                    time: max(0, min(finiteTime(symbol.time), duration)),
                    measureNumber: max(1, symbol.measureNumber),
                    offsetInQuarterNotes: max(0, finiteTime(symbol.offsetInQuarterNotes)),
                    rawText: symbol.rawText
                )
            }
            .sorted {
                if abs($0.time - $1.time) > 0.000_001 {
                    return $0.time < $1.time
                }

                if abs($0.offsetInQuarterNotes - $1.offsetInQuarterNotes) > 0.000_001 {
                    return $0.offsetInQuarterNotes < $1.offsetInQuarterNotes
                }

                return $0.id.uuidString < $1.id.uuidString
            }
    }

    static func normalizedNotationItems(
        _ items: [NotationMeasureItem],
        duration: TimeInterval,
        notationPartClefs: [NotationPartID: Clef]
    ) -> [NotationMeasureItem] {
        let duration = normalizedDuration(duration)
        let persistedItems = items.filter { item in
            !item.isSynthesized
                && (item.kind == .rest || item.pitch != nil)
                && item.measureStartTime.isFinite
                && item.measureStartTime >= 0
                && item.measureStartTime <= duration
                && item.offsetInQuarterNotes.isFinite
                && item.durationInQuarterNotes.isFinite
                && item.durationInQuarterNotes > 0
        }
        let availableItemsByID = persistedItems.reduce(into: [String: NotationMeasureItem]()) {
            if $0[$1.id] == nil { $0[$1.id] = $1 }
        }
        return persistedItems
            .map { item in
                NotationMeasureItem(
                    id: item.id,
                    partID: item.partID,
                    kind: item.kind,
                    pitch: item.kind == .note ? item.pitch : nil,
                    explicitAccidental: item.kind == .note
                        && NotationPartClefOverrides.clef(
                            for: item.partID,
                            in: notationPartClefs
                        ) != .drums
                        ? item.explicitAccidental
                        : nil,
                    measureNumber: max(1, item.measureNumber),
                    measureStartTime: min(max(0, finiteTime(item.measureStartTime)), duration),
                    offsetInQuarterNotes: max(0, finiteTime(item.offsetInQuarterNotes)),
                    durationInQuarterNotes: max(0, finiteTime(item.durationInQuarterNotes)),
                    displayDuration: item.displayDuration,
                    tieTargetItemID: normalizedTieTargetItemID(
                        for: item,
                        availableItemsByID: availableItemsByID
                    ),
                    isSynthesized: false
                )
            }
            .sorted {
                if $0.partID.rawValue != $1.partID.rawValue {
                    return notationPartSortKey($0.partID) < notationPartSortKey($1.partID)
                }

                if $0.measureNumber != $1.measureNumber {
                    return $0.measureNumber < $1.measureNumber
                }

                if abs($0.measureStartTime - $1.measureStartTime) > 0.000_001 {
                    return $0.measureStartTime < $1.measureStartTime
                }

                if abs($0.offsetInQuarterNotes - $1.offsetInQuarterNotes) > 0.000_001 {
                    return $0.offsetInQuarterNotes < $1.offsetInQuarterNotes
                }

                return $0.id < $1.id
            }
    }

    static func normalizedStemTranscriptionTracks(
        _ tracks: [StemTranscriptionTrack],
        duration: TimeInterval,
        notationItems: [NotationMeasureItem]
    ) -> [StemTranscriptionTrack] {
        let duration = normalizedDuration(duration)
        let notationItemsByID = Dictionary(
            notationItems.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return acceptedStemTranscriptionTracks(tracks).map { acceptedTrack in
            let track = acceptedTrack.track
            let partID = acceptedTrack.partID
            let notes = track.notes.compactMap { note -> StemTranscriptionNote? in
                guard (0...127).contains(note.midiPitch),
                      note.rawStartTimeSeconds.isFinite,
                      note.rawEndTimeSeconds.isFinite,
                      note.rawStartTimeSeconds >= 0,
                      note.rawEndTimeSeconds > note.rawStartTimeSeconds,
                      note.projectStartTimeSeconds.isFinite,
                      note.projectEndTimeSeconds.isFinite,
                      note.projectEndTimeSeconds > note.projectStartTimeSeconds,
                      note.confidence.isFinite
                else {
                    return nil
                }
                let projectStart = min(duration, max(0, note.projectStartTimeSeconds))
                let projectEnd = min(duration, max(0, note.projectEndTimeSeconds))
                guard projectEnd > projectStart else { return nil }

                return StemTranscriptionNote(
                    id: note.id,
                    midiPitch: note.midiPitch,
                    rawStartTimeSeconds: note.rawStartTimeSeconds,
                    rawEndTimeSeconds: note.rawEndTimeSeconds,
                    projectStartTimeSeconds: projectStart,
                    projectEndTimeSeconds: projectEnd,
                    confidence: min(1, max(0, note.confidence)),
                    pitchBends: note.pitchBends,
                    notationItemIDs: note.notationItemIDs.filter {
                        notationItemsByID[$0]?.partID == partID
                    }
                )
            }
            let timings = track.timings.flatMap(normalizedTranscriptionTimings)
            return StemTranscriptionTrack(
                id: track.id,
                stemType: track.stemType,
                notationPartID: partID,
                sourceFingerprint: track.sourceFingerprint,
                createdAt: track.createdAt,
                configuration: track.configuration,
                notes: notes,
                timings: timings,
                warnings: track.warnings
            )
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    static func acceptedStemTranscriptionTracks(
        _ tracks: [StemTranscriptionTrack]
    ) -> [(track: StemTranscriptionTrack, partID: NotationPartID)] {
        var seenTrackIDs = Set<UUID>()

        return tracks.compactMap { track in
            guard seenTrackIDs.insert(track.id).inserted,
                  !track.sourceFingerprint.path.isEmpty,
                  track.sourceFingerprint.fileSize >= 0,
                  track.sourceFingerprint.modificationTime.isFinite
            else {
                return nil
            }

            let partID = track.notationPartID.stemType == track.stemType
                ? track.notationPartID
                : .stem(track.stemType)
            return (track, partID)
        }
    }

    private static func normalizedTranscriptionTimings(
        _ timings: StemTranscriptionTimings
    ) -> StemTranscriptionTimings? {
        let values = [
            timings.audioPreparationSeconds,
            timings.modelLoadSeconds,
            timings.inferenceSeconds,
            timings.postProcessingSeconds,
            timings.totalSeconds,
            timings.processedDurationSeconds
        ]
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        return timings
    }

    private static func normalizedTieTargetItemID(
        for item: NotationMeasureItem,
        availableItemsByID: [String: NotationMeasureItem]
    ) -> String? {
        guard item.kind == .note,
              let targetID = item.tieTargetItemID,
              targetID != item.id,
              let target = availableItemsByID[targetID],
              target.kind == .note,
              target.partID == item.partID,
              target.pitch == item.pitch
        else {
            return nil
        }
        return targetID
    }

    private static func notationPartSortKey(_ partID: NotationPartID) -> String {
        if partID == .main {
            return "0-main"
        }

        if let stemType = partID.stemType,
           let index = StemType.allCases.firstIndex(of: stemType) {
            return "1-\(String(format: "%02d", index))-\(stemType.rawValue)"
        }

        return "9-\(partID.rawValue)"
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
