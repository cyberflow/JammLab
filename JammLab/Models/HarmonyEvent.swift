import Foundation

struct HarmonyBeatKey: Hashable, Comparable {
    var value: Int

    init(_ beat: Double) {
        guard beat.isFinite else {
            value = 0
            return
        }

        value = max(0, Int(beat.rounded()))
    }

    init(value: Int) {
        self.value = max(0, value)
    }

    var startBeat: Double {
        Double(value)
    }

    static func < (lhs: HarmonyBeatKey, rhs: HarmonyBeatKey) -> Bool {
        lhs.value < rhs.value
    }
}

struct HarmonyEvent: Identifiable, Codable, Equatable {
    static let defaultSymbol = "N.C."

    var id: UUID
    var startBeat: Double
    var symbol: String

    init(id: UUID = UUID(), startBeat: Double, symbol: String = Self.defaultSymbol) {
        self.id = id
        self.startBeat = HarmonyBeatKey(startBeat).startBeat
        self.symbol = symbol
    }

    var beatKey: HarmonyBeatKey {
        HarmonyBeatKey(startBeat)
    }
}

enum HarmonyEventNormalizer {
    static func normalizedSymbol(_ symbol: String) -> String? {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedEvents(_ events: [HarmonyEvent], maximumBeat: Double? = nil) -> [HarmonyEvent] {
        let maxKey = maximumBeat.map { HarmonyBeatKey($0).value }
        var usedKeys = Set<Int>()

        return events.compactMap { event -> HarmonyEvent? in
            guard let symbol = normalizedSymbol(event.symbol) else { return nil }

            var key = normalizedBeatKey(event.startBeat, maximumKey: maxKey)
            while usedKeys.contains(key.value) {
                guard let nextKey = nextFreeBeatKey(startingAt: key.value + 1, usedKeys: usedKeys, maximumKey: maxKey) else {
                    return nil
                }
                key = nextKey
            }

            usedKeys.insert(key.value)
            return HarmonyEvent(id: event.id, startBeat: key.startBeat, symbol: symbol)
        }
        .sorted { lhs, rhs in
            if lhs.beatKey == rhs.beatKey {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.beatKey < rhs.beatKey
        }
    }

    static func occupiedEventID(
        at key: HarmonyBeatKey,
        in events: [HarmonyEvent],
        excluding excludedID: HarmonyEvent.ID? = nil
    ) -> HarmonyEvent.ID? {
        events.first { event in
            event.id != excludedID && event.beatKey == key
        }?.id
    }

    static func nearestFreeBeatKey(
        from proposedBeat: Double,
        in events: [HarmonyEvent],
        excluding excludedID: HarmonyEvent.ID? = nil,
        maximumBeat: Double? = nil
    ) -> HarmonyBeatKey? {
        let maxKey = maximumBeat.map { HarmonyBeatKey($0).value }
        let proposedKey = normalizedBeatKey(proposedBeat, maximumKey: maxKey)
        let usedKeys = Set(events.compactMap { event -> Int? in
            event.id == excludedID ? nil : event.beatKey.value
        })

        if !usedKeys.contains(proposedKey.value) {
            return proposedKey
        }

        return nextFreeBeatKey(startingAt: proposedKey.value + 1, usedKeys: usedKeys, maximumKey: maxKey)
    }

    private static func normalizedBeatKey(_ beat: Double, maximumKey: Int?) -> HarmonyBeatKey {
        let rawKey = HarmonyBeatKey(beat)
        guard let maximumKey else { return rawKey }
        return HarmonyBeatKey(value: min(rawKey.value, max(0, maximumKey)))
    }

    private static func nextFreeBeatKey(
        startingAt startKey: Int,
        usedKeys: Set<Int>,
        maximumKey: Int?
    ) -> HarmonyBeatKey? {
        var candidate = max(0, startKey)
        while maximumKey.map({ candidate <= $0 }) ?? true {
            if !usedKeys.contains(candidate) {
                return HarmonyBeatKey(value: candidate)
            }
            candidate += 1
        }

        return nil
    }
}
