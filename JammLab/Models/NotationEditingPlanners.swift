import Foundation

enum NotationPartStatePlanner {
    static func knownStemTypes(
        stemFiles: [StemFile],
        notationItems: [NotationMeasureItem],
        collapsedStemTypes: Set<StemType>,
        visiblePartIDs: Set<NotationPartID>
    ) -> [StemType] {
        let knownTypes = Set(stemFiles.map(\.type))
            .union(notationItems.compactMap(\.partID.stemType))
            .union(collapsedStemTypes)
            .union(visiblePartIDs.compactMap(\.stemType))
        return StemType.allCases.filter { knownTypes.contains($0) }
    }

    static func availableParts(
        knownStemTypes: [StemType],
        transcriptionTracks: [StemTranscriptionTrack]
    ) -> [NotationPartDescriptor] {
        let stemParts = knownStemTypes.map(NotationPartDescriptor.stem)
        let additionalTranscriptions = StemType.allCases.flatMap { stemType in
            transcriptionTracks
                .filter {
                    $0.stemType == stemType
                        && $0.notationPartID != .stem(stemType)
                }
                .sorted { $0.createdAt < $1.createdAt }
                .enumerated()
                .map { index, track in
                    NotationPartDescriptor.stemTranscription(
                        stemType,
                        id: track.notationPartID,
                        sequence: index + 2
                    )
                }
        }
        return [.main] + stemParts + additionalTranscriptions
    }

    static func normalizedVisiblePartIDs(
        _ rawPartIDs: Set<NotationPartID>,
        availableParts: [NotationPartDescriptor]
    ) -> Set<NotationPartID> {
        let allowedPartIDs = Set(availableParts.map(\.id))
        var normalized = rawPartIDs.intersection(allowedPartIDs)
        if normalized.isEmpty {
            normalized = allowedPartIDs.contains(.main) ? [.main] : Set(allowedPartIDs.prefix(1))
        }
        return normalized
    }
}

struct NotationAccidentalEditPlan {
    var chainIDs: Set<String>
    var rootItemID: String
    var alreadyApplied: Bool
    var updatedItems: [NotationMeasureItem]
}

enum NotationAccidentalPlanner {
    static func plan(
        accidental: NotationAccidental,
        selectedItem: NotationMeasureItem,
        measure: ScoreMeasure,
        allItems: [NotationMeasureItem]
    ) -> NotationAccidentalEditPlan? {
        guard selectedItem.kind == .note,
              selectedItem.pitch != nil,
              measure.attributes.clef != .drums
        else {
            return nil
        }

        let chainIDs = NotationNoteEditPlanner.logicalChainItemIDs(
            in: allItems,
            containing: selectedItem.id,
            partID: selectedItem.partID
        )
        guard !chainIDs.isEmpty else { return nil }

        let chainItems = allItems.filter { chainIDs.contains($0.id) }
        let incomingTargetIDs = Set(chainItems.compactMap(\.tieTargetItemID))
        let rootItemID = chainItems.first(where: { !incomingTargetIDs.contains($0.id) })?.id
            ?? selectedItem.id

        let hasCollision = chainItems.contains { chainItem in
            guard var pitch = chainItem.pitch else { return true }
            pitch.alter = accidental.alter
            return allItems.contains { candidate in
                !chainIDs.contains(candidate.id)
                    && candidate.partID == chainItem.partID
                    && candidate.kind == .note
                    && candidate.pitch?.midiNoteNumber == pitch.midiNoteNumber
                    && candidate.measureNumber == chainItem.measureNumber
                    && abs(candidate.measureStartTime - chainItem.measureStartTime)
                        < NotationMeasureTiming.timelineTolerance
                    && abs(candidate.offsetInQuarterNotes - chainItem.offsetInQuarterNotes)
                        < NotationMeasureTiming.timelineTolerance
            }
        }
        guard !hasCollision else { return nil }

        let alreadyApplied = chainItems.allSatisfy { item in
            item.pitch?.alter == accidental.alter
                && item.explicitAccidental == (item.id == rootItemID ? accidental : nil)
        }
        let updatedItems = allItems.map { item -> NotationMeasureItem in
            guard chainIDs.contains(item.id), var pitch = item.pitch else { return item }
            pitch.alter = accidental.alter
            var updated = item
            updated.pitch = pitch
            updated.explicitAccidental = item.id == rootItemID ? accidental : nil
            return updated
        }

        return NotationAccidentalEditPlan(
            chainIDs: chainIDs,
            rootItemID: rootItemID,
            alreadyApplied: alreadyApplied,
            updatedItems: updatedItems
        )
    }
}
