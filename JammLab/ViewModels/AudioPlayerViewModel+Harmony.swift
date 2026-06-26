import Foundation

extension AudioPlayerViewModel {
    var harmonyBeatMapper: BeatCoordinateMapper {
        BeatCoordinateMapper(tempoMap: tempoMap)
    }

    @discardableResult
    func createHarmonyEvent(at time: TimeInterval) -> HarmonyEvent.ID? {
        guard duration > 0 else { return nil }

        let mapper = harmonyBeatMapper
        let requestedBeat = mapper.snappedBeat(at: time)
        let requestedKey = HarmonyBeatKey(requestedBeat)

        if let existingID = HarmonyEventNormalizer.occupiedEventID(at: requestedKey, in: harmonyEvents) {
            selectedHarmonyEventID = existingID
            return existingID
        }

        var createdID: HarmonyEvent.ID?
        performUndoableEdit("Add Chord") {
            guard let freeKey = HarmonyEventNormalizer.nearestFreeBeatKey(
                from: requestedBeat,
                in: harmonyEvents,
                maximumBeat: mapper.maximumBeat
            ) else { return }

            let event = HarmonyEvent(startBeat: freeKey.startBeat)
            harmonyEvents.append(event)
            normalizeHarmonyEvents()
            selectedHarmonyEventID = event.id
            createdID = event.id
        }
        return createdID
    }

    func selectHarmonyEvent(id: HarmonyEvent.ID?) {
        selectedHarmonyEventID = availableHarmonyEventID(id)
    }

    @discardableResult
    func updateHarmonyEventSymbol(id: HarmonyEvent.ID, symbol: String) -> Bool {
        guard let normalizedSymbol = HarmonyEventNormalizer.normalizedSymbol(symbol) else { return false }

        var didUpdate = false
        performUndoableEdit("Edit Chord") {
            guard let index = harmonyEvents.firstIndex(where: { $0.id == id }) else { return }

            harmonyEvents[index].symbol = normalizedSymbol
            normalizeHarmonyEvents()
            selectedHarmonyEventID = id
            didUpdate = true
        }
        return didUpdate
    }

    func moveHarmonyEvent(id: HarmonyEvent.ID, to time: TimeInterval) {
        guard duration > 0 else { return }

        let mapper = harmonyBeatMapper
        let requestedBeat = mapper.snappedBeat(at: time)
        performUndoableEdit("Move Chord") {
            guard
                let index = harmonyEvents.firstIndex(where: { $0.id == id }),
                let freeKey = HarmonyEventNormalizer.nearestFreeBeatKey(
                    from: requestedBeat,
                    in: harmonyEvents,
                    excluding: id,
                    maximumBeat: mapper.maximumBeat
                )
            else {
                return
            }

            harmonyEvents[index].startBeat = freeKey.startBeat
            normalizeHarmonyEvents()
            selectedHarmonyEventID = id
        }
    }

    func deleteHarmonyEvent(id: HarmonyEvent.ID) {
        performUndoableEdit("Delete Chord") {
            harmonyEvents.removeAll { $0.id == id }

            if selectedHarmonyEventID == id {
                selectedHarmonyEventID = nil
            }
        }
    }

    @discardableResult
    func commitHarmonyEventAndCreateNext(id: HarmonyEvent.ID, symbol: String) -> HarmonyEvent.ID? {
        guard let normalizedSymbol = HarmonyEventNormalizer.normalizedSymbol(symbol) else { return nil }

        var nextID: HarmonyEvent.ID?
        performUndoableEdit("Edit Chord") {
            guard let index = harmonyEvents.firstIndex(where: { $0.id == id }) else { return }

            let currentBeat = harmonyEvents[index].beatKey.value
            harmonyEvents[index].symbol = normalizedSymbol
            if let nextKey = HarmonyEventNormalizer.nearestFreeBeatKey(
                from: Double(currentBeat + 1),
                in: harmonyEvents,
                excluding: id,
                maximumBeat: harmonyBeatMapper.maximumBeat
            ) {
                let event = HarmonyEvent(startBeat: nextKey.startBeat)
                harmonyEvents.append(event)
                nextID = event.id
            } else {
                nextID = id
            }

            normalizeHarmonyEvents()
            selectedHarmonyEventID = nextID
        }

        return nextID
    }

    private func normalizeHarmonyEvents() {
        harmonyEvents = ProjectStateNormalizer.normalizedHarmonyEvents(harmonyEvents, tempoMap: tempoMap)
    }
}
