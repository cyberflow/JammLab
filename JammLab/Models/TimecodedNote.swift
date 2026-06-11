import Foundation

enum MarkerColor: String, CaseIterable, Identifiable, Codable {
    case markerDefault
    case markerOrange
    case markerYellow
    case markerBlue
    case markerPurple
    case regionDefault
    case regionGreen
    case regionAmber
    case regionBlue
    case regionPlum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markerDefault:
            return "Marker Default"
        case .markerOrange:
            return "Marker Orange"
        case .markerYellow:
            return "Marker Yellow"
        case .markerBlue:
            return "Marker Blue"
        case .markerPurple:
            return "Marker Purple"
        case .regionDefault:
            return "Region Default"
        case .regionGreen:
            return "Region Green"
        case .regionAmber:
            return "Region Amber"
        case .regionBlue:
            return "Region Blue"
        case .regionPlum:
            return "Region Plum"
        }
    }

    var defaultHex: String {
        switch self {
        case .markerDefault:
            return "#A00000"
        case .markerOrange:
            return "#B85A00"
        case .markerYellow:
            return "#A88A00"
        case .markerBlue:
            return "#1F6FA8"
        case .markerPurple:
            return "#7A3FA0"
        case .regionDefault:
            return "#567272"
        case .regionGreen:
            return "#66805A"
        case .regionAmber:
            return "#9A8048"
        case .regionBlue:
            return "#5B7188"
        case .regionPlum:
            return "#7A617E"
        }
    }
}

struct NoteColorPreset: Equatable, Identifiable {
    let id: MarkerColor
    let title: String
    let hex: String

    static func presets(for note: TimecodedNote) -> [NoteColorPreset] {
        note.isRegion ? regionPresets : markerPresets
    }

    static let markerPresets: [NoteColorPreset] = [
        NoteColorPreset(id: .markerDefault, title: "Default"),
        NoteColorPreset(id: .markerOrange, title: "Orange"),
        NoteColorPreset(id: .markerYellow, title: "Yellow"),
        NoteColorPreset(id: .markerBlue, title: "Blue"),
        NoteColorPreset(id: .markerPurple, title: "Purple")
    ]

    static let regionPresets: [NoteColorPreset] = [
        NoteColorPreset(id: .regionDefault, title: "Default"),
        NoteColorPreset(id: .regionGreen, title: "Green"),
        NoteColorPreset(id: .regionAmber, title: "Amber"),
        NoteColorPreset(id: .regionBlue, title: "Blue"),
        NoteColorPreset(id: .regionPlum, title: "Plum")
    ]

    init(id: MarkerColor, title: String, hex: String? = nil) {
        self.id = id
        self.title = title
        self.hex = hex ?? id.defaultHex
    }
}

enum TimecodedNoteKind: String, Codable {
    case marker
    case region
    // Legacy value kept so older saved projects reopen as Region notes.
    case loop
}

struct TimecodedNote: Identifiable, Equatable, Codable {
    var id: UUID
    var kind: TimecodedNoteKind
    var time: TimeInterval
    var duration: TimeInterval?
    var title: String
    var color: MarkerColor
    var customColorHex: String?
    var comment: String?
    var metadata: [String: String]?

    var isLoop: Bool {
        kind == .loop
    }

    var isRegion: Bool {
        kind == .region || kind == .loop
    }

    var isMarker: Bool {
        kind == .marker
    }

    var regionEndTime: TimeInterval {
        time + max(0, duration ?? 0)
    }

    var regionRange: LoopRegion? {
        guard isRegion else { return nil }
        return LoopRegion(start: time, end: regionEndTime)
    }

    var resolvedColorHex: String {
        normalizedCustomColorHex ?? color.defaultHex
    }

    var normalizedCustomColorHex: String? {
        Self.normalizedColorHex(customColorHex)
    }

    var hasCustomColor: Bool {
        normalizedCustomColorHex != nil
    }

    // Keep marker data persistence-friendly: only stable values live here.
    // Region-specific fields also live here so future project persistence stays
    // a single Notes source of truth instead of a separate Regions store.
    init(
        id: UUID = UUID(),
        kind: TimecodedNoteKind = .marker,
        time: TimeInterval,
        duration: TimeInterval? = nil,
        title: String,
        color: MarkerColor? = nil,
        customColorHex: String? = nil,
        comment: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.time = time
        self.duration = duration
        self.title = title
        self.color = color ?? Self.defaultColor(for: kind)
        self.customColorHex = Self.normalizedColorHex(customColorHex)
        self.comment = comment
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case time
        case duration
        case title
        case color
        case customColorHex
        case comment
        case metadata
        case endTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = (try? container.decode(TimecodedNoteKind.self, forKey: .kind)) ?? .marker
        time = max(0, try container.decode(TimeInterval.self, forKey: .time))
        title = (try? container.decode(String.self, forKey: .title)) ?? "Marker"
        if
            let colorRawValue = try container.decodeIfPresent(String.self, forKey: .color),
            let decodedColor = MarkerColor(rawValue: colorRawValue)
        {
            color = decodedColor
        } else {
            color = Self.defaultColor(for: kind)
        }
        customColorHex = Self.normalizedColorHex(try container.decodeIfPresent(String.self, forKey: .customColorHex))
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)

        if let storedDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) {
            duration = max(0, storedDuration)
        } else if let legacyEndTime = try container.decodeIfPresent(TimeInterval.self, forKey: .endTime) {
            duration = max(0, legacyEndTime - time)
        } else {
            duration = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(time, forKey: .time)
        try container.encode(title, forKey: .title)
        try container.encode(color, forKey: .color)
        try container.encodeIfPresent(normalizedCustomColorHex, forKey: .customColorHex)
        try container.encodeIfPresent(comment, forKey: .comment)
        try container.encodeIfPresent(metadata, forKey: .metadata)

        if isRegion {
            try container.encode(max(0, duration ?? 0), forKey: .duration)
        }
    }

    static func defaultColor(for kind: TimecodedNoteKind) -> MarkerColor {
        switch kind {
        case .marker:
            return .markerDefault
        case .region, .loop:
            return .regionDefault
        }
    }

    static func normalizedColorHex(_ hex: String?) -> String? {
        guard let hex else { return nil }

        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalized = trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
        let digits = String(normalized.dropFirst())
        guard normalized.count == 7, digits.allSatisfy(\.isHexDigit) else { return nil }
        return normalized
    }
}
