import Foundation

extension AudioPlayerViewModel {
    var regionNotes: [TimecodedNote] {
        notes.filter(\.isRegion)
    }

    func setLoopStartAtCurrentTime() {
        updateLoopStart(currentTime)
    }

    func setLoopEndAtCurrentTime() {
        updateLoopEnd(currentTime)
    }

    func addNoteAtCurrentTime() {
        addNote(at: currentTime)
    }

    func addTempoTimeSignatureMarkerAtCurrentTime(
        bpm: Double,
        beatsPerBar: Int,
        setsNewFirstBeat: Bool = false
    ) {
        addTempoTimeSignatureMarker(
            at: currentTime,
            bpm: bpm,
            beatsPerBar: beatsPerBar,
            setsNewFirstBeat: setsNewFirstBeat
        )
    }

    func addNote(at time: TimeInterval) {
        performUndoableEdit("Add Marker") {
            guard duration > 0 else { return }

            let clampedTime = snappedTimelineTime(time)
            let note = TimecodedNote(
                time: clampedTime,
                title: "Marker \(notes.count + 1)"
            )
            notes.append(note)
            notes.sort { $0.time < $1.time }
        }
    }

    func addTempoTimeSignatureMarker(
        at time: TimeInterval,
        bpm: Double,
        beatsPerBar: Int,
        setsNewFirstBeat: Bool = false
    ) {
        performUndoableEdit("Add Tempo / Time Signature Marker") {
            guard duration > 0 else { return }

            let clampedTime = snappedTimelineTime(time)
            guard let payload = tempoMarkerPayload(
                at: clampedTime,
                bpm: bpm,
                beatsPerBar: beatsPerBar,
                setsNewFirstBeat: setsNewFirstBeat
            ) else { return }
            let note = TimecodedNote(
                time: clampedTime,
                title: payload.title,
                metadata: payload.metadata
            )
            notes.append(note)
            notes.sort { $0.time < $1.time }
            applyTempoMapToPlaybackEngine()
        }
    }

    func saveCurrentLoopRegionAsRegion() {
        performUndoableEdit("Add Region") {
            guard duration > 0, loopRegion.end > loopRegion.start else { return }

            let regionCount = notes.filter(\.isRegion).count
            let note = TimecodedNote(
                kind: .region,
                time: loopRegion.start,
                duration: loopRegion.duration,
                title: "Region \(regionCount + 1)"
            )
            notes.append(note)
            selectedRegionID = note.id
            activeLoopRegionID = nil
            notes.sort { $0.time < $1.time }
        }
    }

    func seek(to note: TimecodedNote) {
        if note.isRegion {
            activateRegionAsLoop(id: note.id, shouldSeek: true)
            return
        }

        seek(to: note.time)
    }

    func selectRegion(id: TimecodedNote.ID?, shouldSeek: Bool = false) {
        guard let id else {
            selectedRegionID = nil
            return
        }

        guard let note = notes.first(where: { $0.id == id && $0.isRegion }) else { return }

        selectedRegionID = id

        if shouldSeek {
            seek(to: note.time)
        }
    }

    func activateRegionAsLoop(id: TimecodedNote.ID, shouldSeek: Bool = false) {
        var seekTime: TimeInterval?
        performUndoableEdit("Activate Region Loop") {
            guard let note = notes.first(where: { $0.id == id && $0.isRegion }) else { return }

            selectedRegionID = id
            activeLoopRegionID = id
            loopRegion = LoopRegion(start: note.time, end: note.regionEndTime).clamped(to: duration)
            applyLoopConfiguration()
            seekTime = note.time
        }

        if shouldSeek, let seekTime {
            seek(to: seekTime)
        }
    }

    func focusRegion(id: TimecodedNote.ID) {
        guard notes.contains(where: { $0.id == id && $0.isRegion }) else { return }
        selectedRegionID = id
    }

    func updateRegionRange(id: TimecodedNote.ID, start: TimeInterval, end: TimeInterval) {
        performUndoableEdit("Edit Region") {
            guard let index = notes.firstIndex(where: { $0.id == id && $0.isRegion }) else { return }

            let snappedStart = snappedTimelineTime(start)
            let snappedEnd = snappedTimelineTime(end)
            let updatedRange = LoopRegion(start: snappedStart, end: snappedEnd)
                .clamped(to: duration, minimumLength: activeRangeMinimumLength)
            notes[index].kind = .region
            notes[index].time = updatedRange.start
            notes[index].duration = updatedRange.duration
            notes.sort { $0.time < $1.time }

            // Region editing is intentionally independent from the current loop range.
            // Double-click a region on the region track when it should become the active loop again.
            if activeLoopRegionID == id {
                activeLoopRegionID = nil
                applyLoopConfiguration()
            }
        }
    }

    func updateNoteTitle(id: TimecodedNote.ID, title: String) {
        performUndoableEdit("Rename Marker") {
            guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
            guard !notes[index].isTempoTimeSignatureMarker else { return }

            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackTitle = notes[index].isRegion ? "Region" : "Marker"
            notes[index].title = trimmedTitle.isEmpty ? fallbackTitle : trimmedTitle
        }
    }

    func updateTempoTimeSignatureMarker(
        id: TimecodedNote.ID,
        bpm: Double,
        beatsPerBar: Int,
        setsNewFirstBeat: Bool = false
    ) {
        performUndoableEdit("Edit Tempo / Time Signature Marker") {
            guard let index = notes.firstIndex(where: { $0.id == id && $0.isTempoTimeSignatureMarker }) else { return }

            let time = notes[index].time
            guard let payload = tempoMarkerPayload(
                at: time,
                bpm: bpm,
                beatsPerBar: beatsPerBar,
                setsNewFirstBeat: setsNewFirstBeat,
                excluding: id
            ) else {
                notes.remove(at: index)
                applyTempoMapToPlaybackEngine()
                return
            }

            notes[index].metadata = payload.metadata
            notes[index].title = payload.title
            notes.sort { $0.time < $1.time }
            applyTempoMapToPlaybackEngine()
        }
    }

    func updateNoteColor(id: TimecodedNote.ID, color: MarkerColor) {
        performUndoableEdit("Change Marker Color") {
            guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
            notes[index].color = color
            notes[index].customColorHex = nil
        }
    }

    func updateNoteCustomColor(id: TimecodedNote.ID, hex: String) {
        performUndoableEdit("Change Marker Color") {
            guard
                let index = notes.firstIndex(where: { $0.id == id }),
                let normalizedHex = TimecodedNote.normalizedColorHex(hex)
            else { return }

            notes[index].customColorHex = normalizedHex
        }
    }

    func updateMarkerTime(id: TimecodedNote.ID, time: TimeInterval) {
        performUndoableEdit("Move Marker") {
            guard let index = notes.firstIndex(where: { $0.id == id && $0.isMarker }) else { return }

            notes[index].time = snappedTimelineTime(time)
            notes.sort { $0.time < $1.time }
            if notes.contains(where: { $0.id == id && $0.isTempoTimeSignatureMarker }) {
                applyTempoMapToPlaybackEngine()
            }
        }
    }

    func deleteNote(id: TimecodedNote.ID) {
        performUndoableEdit("Delete Marker") {
            notes.removeAll { $0.id == id }

            if selectedRegionID == id {
                selectedRegionID = nil
            }

            if activeLoopRegionID == id {
                activeLoopRegionID = nil
                applyLoopConfiguration()
            }

            applyTempoMapToPlaybackEngine()
        }
    }

    func effectiveBeatGridSettings(at time: TimeInterval, excluding noteID: TimecodedNote.ID? = nil) -> BeatGridSettings {
        let sourceNotes = notes.filter { note in
            guard let noteID else { return true }
            return note.id != noteID
        }
        let lookupTime = max(0, time - 0.000_001)
        return TempoMap(baseSettings: beatGridSettings, markers: sourceNotes, duration: duration)
            .settings(at: lookupTime)
    }

    private func tempoMarkerPayload(
        at time: TimeInterval,
        bpm: Double,
        beatsPerBar: Int,
        setsNewFirstBeat: Bool,
        excluding noteID: TimecodedNote.ID? = nil
    ) -> TempoTimeSignatureMarkerPayload? {
        let effectiveSettings = effectiveBeatGridSettings(at: time, excluding: noteID)
        let normalizedBPM = ProjectStateNormalizer.normalizedTempo(bpm)
        let normalizedBeatsPerBar = TimeSignature.normalizedBeatsPerBar(beatsPerBar)
        let bpmChanged = normalizedBPM != nil && abs((normalizedBPM ?? 0) - (effectiveSettings.bpm ?? 0)) > 0.0001
        let signatureChanged = normalizedBeatsPerBar != effectiveSettings.timeSignature.beatsPerBar
        let payload = TempoTimeSignatureMarkerPayload(
            bpm: bpmChanged ? normalizedBPM : nil,
            beatsPerBar: signatureChanged ? normalizedBeatsPerBar : nil,
            setsNewFirstBeat: setsNewFirstBeat
        )
        return payload.hasChanges ? payload : nil
    }

    func updateLoopStart(_ start: TimeInterval) {
        performUndoableEdit("Edit Loop") {
            selectedRegionID = nil
            activeLoopRegionID = nil
            let minimumLength = activeRangeMinimumLength
            let maximumStart = max(0, loopRegion.end - minimumLength)
            let snappedStart = snappedTimelineTime(start)
            loopRegion.start = min(max(0, snappedStart), maximumStart)
            loopRegion = loopRegion.clamped(to: duration, minimumLength: minimumLength)
            applyLoopConfiguration()
        }
    }

    func updateLoopEnd(_ end: TimeInterval) {
        performUndoableEdit("Edit Loop") {
            selectedRegionID = nil
            activeLoopRegionID = nil
            let minimumLength = activeRangeMinimumLength
            let minimumEnd = min(duration, loopRegion.start + minimumLength)
            let snappedEnd = snappedTimelineTime(end)
            loopRegion.end = max(min(snappedEnd, duration), minimumEnd)
            loopRegion = loopRegion.clamped(to: duration, minimumLength: minimumLength)
            applyLoopConfiguration()
        }
    }

    func updateLoopRegion(start: TimeInterval, end: TimeInterval) {
        performUndoableEdit("Edit Loop") {
            selectedRegionID = nil
            activeLoopRegionID = nil
            let minimumLength = activeRangeMinimumLength
            let snappedStart = snappedTimelineTime(start)
            let snappedEnd = snappedTimelineTime(end)
            let lower = max(0, min(snappedStart, snappedEnd))
            let upper = min(duration, max(snappedStart, snappedEnd))
            loopRegion = LoopRegion(start: lower, end: upper).clamped(to: duration, minimumLength: minimumLength)
            applyLoopConfiguration()
        }
    }
}
