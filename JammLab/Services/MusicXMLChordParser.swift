import Foundation

struct MusicXMLChord: Equatable {
    var root: MusicXMLPitchStep
    var kindValue: String
    var displayText: String
    var degrees: [MusicXMLChordDegree]
    var bass: MusicXMLPitchStep?
}

struct MusicXMLPitchStep: Equatable {
    var step: String
    var alter: Int
}

struct MusicXMLChordDegree: Equatable {
    enum DegreeType: String, Equatable {
        case add
        case alter
        case subtract
    }

    var value: Int
    var alter: Int
    var type: DegreeType
}

enum MusicXMLChordParser {
    static func parse(_ rawText: String, measureNumber: Int) throws -> MusicXMLChord {
        let displayText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayText.isEmpty else {
            throw NotationExportError.unsupportedChord(rawText: rawText, measureNumber: measureNumber)
        }

        let normalized = displayText
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "∆", with: "maj")
            .replacingOccurrences(of: "Δ", with: "maj")
            .replacingOccurrences(of: "ø", with: "m7b5")
            .replacingOccurrences(of: "°", with: "dim")
            .replacingOccurrences(of: " ", with: "")

        let slashParts = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard slashParts.count <= 2, let chordPart = slashParts.first, !chordPart.isEmpty else {
            throw NotationExportError.unsupportedChord(rawText: displayText, measureNumber: measureNumber)
        }

        let parsedRoot = parsePitchPrefix(String(chordPart))
        guard let root = parsedRoot.pitch else {
            throw NotationExportError.unsupportedChord(rawText: displayText, measureNumber: measureNumber)
        }

        var suffix = String(chordPart.dropFirst(parsedRoot.length))
        var degrees: [MusicXMLChordDegree] = []
        guard extractParenthesizedDegrees(from: &suffix, into: &degrees) else {
            throw NotationExportError.unsupportedChord(rawText: displayText, measureNumber: measureNumber)
        }
        extractInlineDegrees(from: &suffix, into: &degrees)

        guard let kindValue = kindValue(for: suffix) else {
            throw NotationExportError.unsupportedChord(rawText: displayText, measureNumber: measureNumber)
        }

        let bass: MusicXMLPitchStep?
        if slashParts.count == 2 {
            let bassText = String(slashParts[1])
            let parsedBass = parsePitchPrefix(bassText)
            guard let parsedBassPitch = parsedBass.pitch, parsedBass.length == bassText.count else {
                throw NotationExportError.unsupportedChord(rawText: displayText, measureNumber: measureNumber)
            }
            bass = parsedBassPitch
        } else {
            bass = nil
        }

        return MusicXMLChord(
            root: root,
            kindValue: kindValue,
            displayText: displayText,
            degrees: degrees,
            bass: bass
        )
    }

    private static func parsePitchPrefix(_ text: String) -> (pitch: MusicXMLPitchStep?, length: Int) {
        guard let first = text.first else { return (nil, 0) }
        let step = String(first).uppercased()
        guard ["A", "B", "C", "D", "E", "F", "G"].contains(step) else {
            return (nil, 0)
        }

        let remaining = text.dropFirst()
        if remaining.first == "#" {
            return (MusicXMLPitchStep(step: step, alter: 1), 2)
        }
        if remaining.first == "b" {
            return (MusicXMLPitchStep(step: step, alter: -1), 2)
        }
        return (MusicXMLPitchStep(step: step, alter: 0), 1)
    }

    private static func extractParenthesizedDegrees(
        from suffix: inout String,
        into degrees: inout [MusicXMLChordDegree]
    ) -> Bool {
        while let open = suffix.firstIndex(of: "("),
              let close = suffix[open...].firstIndex(of: ")"),
              open < close {
            let content = suffix[suffix.index(after: open)..<close]
            guard parseDegreeList(String(content), into: &degrees) else {
                return false
            }
            suffix.removeSubrange(open...close)
        }
        return !suffix.contains("(") && !suffix.contains(")")
    }

    private static func extractInlineDegrees(
        from suffix: inout String,
        into degrees: inout [MusicXMLChordDegree]
    ) {
        if ["m7b5", "min7b5"].contains(suffix.lowercased()) {
            return
        }

        let tokens = ["add13", "add11", "add9", "no5", "no3", "#11", "b13", "#9", "b9", "#5", "b5"]
        var didRemove = true
        while didRemove {
            didRemove = false
            for token in tokens {
                if suffix.hasSuffix(token), let degree = degree(from: token) {
                    suffix.removeLast(token.count)
                    degrees.append(degree)
                    didRemove = true
                    break
                }
            }
        }
    }

    private static func parseDegreeList(_ text: String, into degrees: inout [MusicXMLChordDegree]) -> Bool {
        let tokens = text
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !tokens.isEmpty else { return false }

        for token in tokens {
            guard let degree = degree(from: token) else {
                return false
            }
            degrees.append(degree)
        }
        return true
    }

    private static func degree(from token: String) -> MusicXMLChordDegree? {
        let normalized = token.lowercased()
        if normalized.hasPrefix("add"),
           let value = Int(normalized.dropFirst(3)) {
            return MusicXMLChordDegree(value: value, alter: 0, type: .add)
        }
        if normalized.hasPrefix("no"),
           let value = Int(normalized.dropFirst(2)) {
            return MusicXMLChordDegree(value: value, alter: 0, type: .subtract)
        }
        if normalized.hasPrefix("#"),
           let value = Int(normalized.dropFirst()) {
            return MusicXMLChordDegree(value: value, alter: 1, type: .alter)
        }
        if normalized.hasPrefix("b"),
           let value = Int(normalized.dropFirst()) {
            return MusicXMLChordDegree(value: value, alter: -1, type: .alter)
        }
        return nil
    }

    private static func kindValue(for suffix: String) -> String? {
        let normalized = normalizedKindSuffix(suffix)
        let kindValues: [String: String] = [
            "": "major",
            "maj": "major",
            "m": "minor",
            "min": "minor",
            "-": "minor",
            "5": "power",
            "6": "major-sixth",
            "m6": "minor-sixth",
            "min6": "minor-sixth",
            "7": "dominant",
            "maj7": "major-seventh",
            "ma7": "major-seventh",
            "m7": "minor-seventh",
            "min7": "minor-seventh",
            "-7": "minor-seventh",
            "mmaj7": "minor-major-seventh",
            "mm7": "minor-major-seventh",
            "minmaj7": "minor-major-seventh",
            "minm7": "minor-major-seventh",
            "dim": "diminished",
            "o": "diminished",
            "dim7": "diminished-seventh",
            "o7": "diminished-seventh",
            "aug": "augmented",
            "+": "augmented",
            "sus": "suspended-fourth",
            "sus4": "suspended-fourth",
            "sus2": "suspended-second",
            "9": "dominant-ninth",
            "maj9": "major-ninth",
            "m9": "minor-ninth",
            "min9": "minor-ninth",
            "11": "dominant-11th",
            "m11": "minor-11th",
            "min11": "minor-11th",
            "13": "dominant-13th",
            "maj13": "major-13th",
            "m13": "minor-13th",
            "min13": "minor-13th",
            "m7b5": "half-diminished",
            "min7b5": "half-diminished"
        ]

        return kindValues[normalized]
    }

    private static func normalizedKindSuffix(_ suffix: String) -> String {
        if suffix.hasPrefix("M") {
            return "maj" + suffix.dropFirst().lowercased()
        }
        return suffix.lowercased()
    }
}
