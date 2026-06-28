import AppKit
import Foundation

enum AppHotkey: CaseIterable, Hashable {
    case playPause
    case toggleLoop
    case setLoopStart
    case setLoopEnd
    case addNote
    case addHarmonyAtPlaybackMarker
    case addTempoTimeSignatureMarker
    case setBeatOne
    case toggleClick
    case toggleSnap
    case togglePlaybackMode
    case toggleVideoWindow

    // Keep this enum as the single source of truth for keyboard shortcuts.
    // When adding a new handled hotkey, add a case here with its help metadata
    // so the Help > Keyboard Shortcuts page stays up to date automatically.
    init?(event: NSEvent) {
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shortcutModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let relevantModifiers = modifierFlags.intersection(shortcutModifiers)

        switch (event.keyCode, relevantModifiers) {
        case (1, [.option]):
            self = .toggleSnap
        case (9, [.option]):
            self = .toggleVideoWindow
        case (8, [.shift]):
            self = .addTempoTimeSignatureMarker
        default:
            guard relevantModifiers.isEmpty else {
                return nil
            }

            self.init(keyCode: event.keyCode)
        }
    }

    private init?(keyCode: UInt16) {
        switch keyCode {
        case 49:
            self = .playPause
        case 48:
            self = .togglePlaybackMode
        case 37:
            self = .toggleLoop
        case 33:
            self = .setLoopStart
        case 30:
            self = .setLoopEnd
        case 46:
            self = .addNote
        case 0:
            self = .addHarmonyAtPlaybackMarker
        case 11:
            self = .setBeatOne
        case 8:
            self = .toggleClick
        default:
            return nil
        }
    }

    var key: String {
        switch self {
        case .playPause:
            return "Space"
        case .toggleLoop:
            return "L"
        case .setLoopStart:
            return "["
        case .setLoopEnd:
            return "]"
        case .addNote:
            return "M"
        case .addHarmonyAtPlaybackMarker:
            return "A"
        case .addTempoTimeSignatureMarker:
            return "Shift+C"
        case .setBeatOne:
            return "B"
        case .toggleClick:
            return "C"
        case .toggleSnap:
            return "Opt+S"
        case .togglePlaybackMode:
            return "Tab"
        case .toggleVideoWindow:
            return "Opt+V"
        }
    }

    var title: String {
        switch self {
        case .playPause:
            return "Play / Stop"
        case .toggleLoop:
            return "Loop On / Off"
        case .setLoopStart:
            return "Set Loop Start"
        case .setLoopEnd:
            return "Set Loop End"
        case .addNote:
            return "Add Marker"
        case .addHarmonyAtPlaybackMarker:
            return "Add Harmony"
        case .addTempoTimeSignatureMarker:
            return "Add Tempo / Time Signature Marker"
        case .setBeatOne:
            return "Set Beat 1"
        case .toggleClick:
            return "Click On / Off"
        case .toggleSnap:
            return "Snap On / Off"
        case .togglePlaybackMode:
            return "Original / Stems"
        case .toggleVideoWindow:
            return "Video Window"
        }
    }

    var detail: String {
        switch self {
        case .playPause:
            return "Start playback from the position marker or stop and return to it."
        case .toggleLoop:
            return "Enable or disable looping for the selected region."
        case .setLoopStart:
            return "Move loop start to the current playback position."
        case .setLoopEnd:
            return "Move loop end to the current playback position."
        case .addNote:
            return "Add a timecoded note at the current playback position."
        case .addHarmonyAtPlaybackMarker:
            return "Open a harmony editor at the position marker, snapped to the Notation track resolution."
        case .addTempoTimeSignatureMarker:
            return "Add a tempo or time signature change marker at the current playback position."
        case .setBeatOne:
            return "Set the current playback position as the first strong beat."
        case .toggleClick:
            return "Enable or disable the beat-grid click overlay."
        case .toggleSnap:
            return "Snap playback cursor, loop and region edits to the nearest beat."
        case .togglePlaybackMode:
            return "Switch between original playback and stems playback when stems are available."
        case .toggleVideoWindow:
            return "Open or close the sidecar video window for the current video project."
        }
    }
}
