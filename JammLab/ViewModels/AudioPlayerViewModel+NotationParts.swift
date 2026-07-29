import Foundation

extension AudioPlayerViewModel {
    var canShowNotationWindow: Bool {
        duration > 0
    }

    var availableNotationParts: [NotationPartDescriptor] {
        NotationPartStatePlanner.availableParts(
            knownStemTypes: knownStemNotationPartTypes(),
            transcriptionTracks: stemTranscriptionTracks
        )
    }

    var visibleNotationParts: [NotationPartDescriptor] {
        let visibleIDs = normalizedVisibleNotationPartIDs()
        return availableNotationParts.filter { visibleIDs.contains($0.id) }
    }

    func isStemNotationTrackCollapsed(_ stemType: StemType) -> Bool {
        stemNotationTrackCollapsed[stemType] ?? true
    }

    func stemNoteDisplayMode(for stemType: StemType) -> StemNoteDisplayMode {
        stemNoteDisplayModes[stemType] ?? .notation
    }

    func toggleStemNoteDisplayMode(_ stemType: StemType) {
        let nextMode: StemNoteDisplayMode = stemNoteDisplayMode(for: stemType) == .notation
            ? .midi
            : .notation
        if nextMode == .midi {
            stemNoteDisplayModes[stemType] = .midi
        } else {
            stemNoteDisplayModes.removeValue(forKey: stemType)
        }
        stemNotationTrackCollapsed[stemType] = false
        refreshProjectModifiedState()
    }

    func toggleNotationWindowPartVisibility(_ partID: NotationPartID) {
        var next = normalizedVisibleNotationPartIDs()
        if next.contains(partID) {
            next.remove(partID)
        } else {
            next.insert(partID)
        }

        let normalized = normalizedVisibleNotationPartIDs(from: next)
        guard normalized != visibleNotationPartIDs else { return }
        visibleNotationPartIDs = normalized
        refreshProjectModifiedState()
    }

    func normalizedVisibleNotationPartIDs(
        from rawPartIDs: Set<NotationPartID>? = nil
    ) -> Set<NotationPartID> {
        NotationPartStatePlanner.normalizedVisiblePartIDs(
            rawPartIDs ?? visibleNotationPartIDs,
            availableParts: availableNotationParts
        )
    }

    func notationClef(for partID: NotationPartID) -> Clef {
        NotationPartClefOverrides.clef(for: partID, in: notationPartClefs)
    }

    func setNotationClef(_ clef: Clef, for partID: NotationPartID) {
        let sourceClef = notationClef(for: partID)
        guard sourceClef != clef else { return }

        let octaveDelta = sourceClef == .drums || clef == .drums
            ? 0
            : clef.notationMetrics.storedPitchOctaveOffset
                - sourceClef.notationMetrics.storedPitchOctaveOffset
        let candidateItems = notationItems.map { item -> NotationMeasureItem in
            guard item.partID == partID,
                  !item.isSynthesized,
                  item.kind == .note,
                  var pitch = item.pitch
            else {
                return item
            }

            pitch.octave += octaveDelta
            var transposed = item
            transposed.pitch = pitch
            if clef == .drums {
                transposed.explicitAccidental = nil
            }
            return transposed
        }
        let invalidPitch = candidateItems.first { item in
            item.partID == partID
                && item.kind == .note
                && item.pitch.map { !NotationInputPolicy.isEditable($0, in: clef) } == true
        }?.pitch
        guard invalidPitch == nil else {
            errorMessage = "Cannot change to \(clef.displayName): the part contains notes outside the supported input map."
            return
        }

        errorMessage = nil
        performUndoableEdit("Change Notation Clef") {
            if clef == NotationPartClefOverrides.defaultClef(for: partID) {
                notationPartClefs.removeValue(forKey: partID)
            } else {
                notationPartClefs[partID] = clef
            }

            notationItems = candidateItems
            notationItems = ProjectStateNormalizer.normalizedNotationItems(
                notationItems,
                duration: duration,
                notationPartClefs: notationPartClefs
            )
            refreshNotationSelections(for: partID)
        }
    }

    func selectDrumInstrument(midiNoteNumber: Int) {
        guard DrumInstrumentMap.allowedMIDINoteNumbers.contains(midiNoteNumber) else { return }
        selectedDrumInstrumentMIDINoteNumber = midiNoteNumber
        let pitch = NotationPitchMapper.pitch(
            forMIDINoteNumber: midiNoteNumber,
            keySignature: .cMajor
        )
        auditionNotationNotePitch(pitch, clef: .drums)
    }

    private func knownStemNotationPartTypes() -> [StemType] {
        NotationPartStatePlanner.knownStemTypes(
            stemFiles: stemFiles,
            notationItems: notationItems,
            collapsedStemTypes: Set(stemNotationTrackCollapsed.keys),
            visiblePartIDs: visibleNotationPartIDs
        )
    }
}
