enum ControlHelpText {
    static let goToStart = "Go to start"
    static let goToEnd = "Go to end"
    static let play = "Play from position marker"
    static let pause = "Pause and move position marker here"
    static let stop = "Stop and return to position marker"
    static let activateLoop = "Activate loop section"
    static let deactivateLoop = "Deactivate loop section"

    static let tempo = "Tempo"
    static let timeSignature = "Time signature"
    static let key = "Project key"
    static let harmonyInputResolution = "Harmony input resolution"
    static let click = "Click on/off (C). Right-click to adjust volume."
    static let clickVolume = "Click volume"
    static let snap = "Snap playback cursor, loop and region edits to the nearest beat (Opt+S)"
    static let setBeatOne = "Set current playback position as Beat 1 (B). Right-click for reset and nudge."
    static let resetBeatGrid = "Reset beat grid"
    static let openTuner = "Open tuner"
    static let separateStems = "Separate the loaded audio into stems"
    static let cancelStemSeparation = "Cancel stem separation"
    static let playbackMode = "Switch playback mode (Tab)"
    static let playbackModeUnavailable = "Stem playback is available after stems are separated"
    static let pitch = "Pitch"
    static let speed = "Speed"

    static let trackVolume = "Track Volume"
    static let mainTrackVolume = "Main Track Volume"
    static let timelineViewport = "Timeline viewport"
    static let timelinePanLeft = "Move timeline left"
    static let timelinePanRight = "Move timeline right"
    static let timelineZoomIn = "Zoom in"
    static let timelineZoomOut = "Zoom out"

    static let resetThemeColors = "Reset theme colors to defaults"
    static let resetClickDefaults = "Restore the current built-in click sound: 1760/1120 Hz and 36/26 ms."
    static let refreshAudioDevices = "Refresh audio device list"
    static let resetAudioDevices = "Reset audio input and output to the system default devices"

    static func muteTrack(_ title: String) -> String {
        "Mute \(title)"
    }

    static func soloTrack(_ title: String) -> String {
        "Solo \(title)"
    }

    static func trackVolume(_ title: String) -> String {
        "\(title) Volume"
    }

    static func beatGridNudge(_ title: String) -> String {
        "Nudge beat grid \(title)"
    }
}
