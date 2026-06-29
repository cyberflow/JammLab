import Foundation

enum ProjectKeySource: String, Codable, Equatable {
    case auto
    case user
}

enum ProjectKeyTonic: String, Codable, CaseIterable, Identifiable {
    case c = "C"
    case cSharpDb = "C#/Db"
    case d = "D"
    case dSharpEb = "D#/Eb"
    case e = "E"
    case f = "F"
    case fSharpGb = "F#/Gb"
    case g = "G"
    case gSharpAb = "G#/Ab"
    case a = "A"
    case aSharpBb = "A#/Bb"
    case b = "B"

    var id: String { rawValue }
    var displayName: String { rawValue }

    func canonicalTonic(for mode: KeySignature.Mode) -> String {
        switch (self, mode) {
        case (.c, _): return "C"
        case (.cSharpDb, .major): return "Db"
        case (.cSharpDb, .minor): return "C#"
        case (.d, _): return "D"
        case (.dSharpEb, .major): return "Eb"
        case (.dSharpEb, .minor): return "D#"
        case (.e, _): return "E"
        case (.f, _): return "F"
        case (.fSharpGb, _): return "F#"
        case (.g, _): return "G"
        case (.gSharpAb, .major): return "Ab"
        case (.gSharpAb, .minor): return "G#"
        case (.a, _): return "A"
        case (.aSharpBb, _): return "Bb"
        case (.b, _): return "B"
        }
    }

    static func tonic(forCanonicalName tonic: String) -> ProjectKeyTonic? {
        switch tonic {
        case "C": return .c
        case "C#", "Db": return .cSharpDb
        case "D": return .d
        case "D#", "Eb": return .dSharpEb
        case "E": return .e
        case "F": return .f
        case "F#", "Gb": return .fSharpGb
        case "G": return .g
        case "G#", "Ab": return .gSharpAb
        case "A": return .a
        case "A#", "Bb": return .aSharpBb
        case "B": return .b
        default: return nil
        }
    }
}

struct ProjectKeySelection: Codable, Equatable {
    var tonic: ProjectKeyTonic
    var mode: KeySignature.Mode
    var source: ProjectKeySource
    var confidence: Double?

    static func defaultSelection(source: ProjectKeySource = .user) -> ProjectKeySelection {
        ProjectKeySelection(
            tonic: .c,
            mode: .major,
            source: source,
            confidence: nil
        )
    }

    var canonicalKeyName: String {
        "\(tonic.canonicalTonic(for: mode)) \(mode.rawValue)"
    }

    var displayName: String {
        "\(tonic.displayName) \(mode.displayName)"
    }

    var asUserSelection: ProjectKeySelection {
        ProjectKeySelection(
            tonic: tonic,
            mode: mode,
            source: .user,
            confidence: nil
        )
    }

    static func detected(from keyName: String?, confidence: Double) -> ProjectKeySelection? {
        guard let keyName else { return nil }
        let normalized = keyName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "Major", with: "major")
            .replacingOccurrences(of: "Minor", with: "minor")
            .replacingOccurrences(of: "MAJOR", with: "major")
            .replacingOccurrences(of: "MINOR", with: "minor")
        guard !normalized.isEmpty else { return nil }

        let lowercased = normalized.lowercased()
        guard lowercased != "pending", lowercased != "unknown" else { return nil }

        let mode: KeySignature.Mode
        var tonicName = normalized
        if lowercased.hasSuffix(" major") {
            mode = .major
            tonicName = String(normalized.dropLast(" major".count))
        } else if lowercased.hasSuffix(" minor") {
            mode = .minor
            tonicName = String(normalized.dropLast(" minor".count))
        } else if lowercased.hasSuffix(" maj") {
            mode = .major
            tonicName = String(normalized.dropLast(" maj".count))
        } else if lowercased.hasSuffix(" min") {
            mode = .minor
            tonicName = String(normalized.dropLast(" min".count))
        } else if lowercased.hasSuffix("m"), normalized.count > 1 {
            mode = .minor
            tonicName = String(normalized.dropLast())
        } else {
            mode = .major
        }

        let canonicalTonic = normalizedTonic(tonicName)
        guard let tonic = ProjectKeyTonic.tonic(forCanonicalName: canonicalTonic) else { return nil }
        return ProjectKeySelection(
            tonic: tonic,
            mode: mode,
            source: .auto,
            confidence: confidence.isFinite ? confidence : nil
        )
    }

    private static func normalizedTonic(_ tonic: String) -> String {
        let compact = tonic
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        guard let first = compact.first else { return compact }
        return first.uppercased() + compact.dropFirst()
    }
}
