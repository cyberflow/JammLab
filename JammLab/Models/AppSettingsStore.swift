import Combine
import Foundation

struct ClickSoundSettings: Codable, Equatable {
    static let defaultValue = ClickSoundSettings(
        accentFrequencyHz: 1_760,
        regularFrequencyHz: 1_120,
        accentLengthMs: 36,
        regularLengthMs: 26
    )

    static let frequencyRange = 100.0...8_000.0
    static let lengthRange = 1.0...200.0

    var accentFrequencyHz: Double
    var regularFrequencyHz: Double
    var accentLengthMs: Double
    var regularLengthMs: Double

    func clamped() -> ClickSoundSettings {
        ClickSoundSettings(
            accentFrequencyHz: Self.clamp(accentFrequencyHz, to: Self.frequencyRange),
            regularFrequencyHz: Self.clamp(regularFrequencyHz, to: Self.frequencyRange),
            accentLengthMs: Self.clamp(accentLengthMs, to: Self.lengthRange),
            regularLengthMs: Self.clamp(regularLengthMs, to: Self.lengthRange)
        )
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}

enum StemBackendComputeMode: String, Codable, CaseIterable, Identifiable {
    case cpuOnly
    case auto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpuOnly:
            return "CPU Only"
        case .auto:
            return "Auto"
        }
    }

    var helperArgument: String {
        switch self {
        case .cpuOnly:
            return "cpu"
        case .auto:
            return "auto"
        }
    }
}

struct AudioDeviceSettings: Codable, Equatable {
    static let defaultValue = AudioDeviceSettings(inputDeviceUID: nil, outputDeviceUID: nil)

    var inputDeviceUID: String?
    var outputDeviceUID: String?

    func normalized() -> AudioDeviceSettings {
        AudioDeviceSettings(
            inputDeviceUID: Self.normalizedUID(inputDeviceUID),
            outputDeviceUID: Self.normalizedUID(outputDeviceUID)
        )
    }

    private static func normalizedUID(_ uid: String?) -> String? {
        guard let uid else { return nil }
        let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum AppColorRole: String, Codable, CaseIterable, Identifiable {
    case appBackground
    case panelBackground
    case elevatedSurface
    case controlBackground
    case controlHover
    case controlActive
    case loopButtonActive
    case border
    case primaryText
    case secondaryText
    case tertiaryText
    case disabledText
    case accent
    case accentHover
    case accentPressed
    case statusButtonFill
    case statusButtonCriticalFill
    case statusButtonAttentionFill
    case valueSliderFill
    case waveformBackground
    case waveformColor
    case waveformDisabledBackground
    case waveformDisabledColor
    case harmonyTrackBackground
    case timeTrackAccentBeatLine
    case timeTrackBeatLine
    case waveformAccentBeatLine
    case waveformBeatLine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appBackground:
            return "App Background"
        case .panelBackground:
            return "Panel Background"
        case .elevatedSurface:
            return "Elevated Surface"
        case .controlBackground:
            return "Control Background"
        case .controlHover:
            return "Control Hover"
        case .controlActive:
            return "Control Active"
        case .loopButtonActive:
            return "Loop Button Active"
        case .border:
            return "Border/Subtle Line"
        case .primaryText:
            return "Primary Text"
        case .secondaryText:
            return "Secondary Text"
        case .tertiaryText:
            return "Tertiary Text"
        case .disabledText:
            return "Disabled Text"
        case .accent:
            return "Accent"
        case .accentHover:
            return "Accent Hover"
        case .accentPressed:
            return "Accent Pressed"
        case .statusButtonFill:
            return "Status Button Fill"
        case .statusButtonCriticalFill:
            return "Status Button Critical Fill"
        case .statusButtonAttentionFill:
            return "Status Button Attention Fill"
        case .valueSliderFill:
            return "Value Slider Fill"
        case .waveformBackground:
            return "Waveform Background"
        case .waveformColor:
            return "Waveform Color"
        case .waveformDisabledBackground:
            return "Waveform Disabled Background"
        case .waveformDisabledColor:
            return "Waveform Disabled Color"
        case .harmonyTrackBackground:
            return "Harmony Track Background"
        case .timeTrackAccentBeatLine:
            return "Time-Track Accent Beat Line"
        case .timeTrackBeatLine:
            return "Time-Track Beat Line"
        case .waveformAccentBeatLine:
            return "Waveform Accent Beat Line"
        case .waveformBeatLine:
            return "Waveform Beat Line"
        }
    }

    var defaultHex: String {
        switch self {
        case .appBackground:
            return "#2A2A2A"
        case .panelBackground:
            return "#363636"
        case .elevatedSurface:
            return "#282828"
        case .controlBackground:
            return "#303030"
        case .controlHover:
            return "#3A3A3A"
        case .controlActive:
            return "#878787"
        case .loopButtonActive:
            return "#3CAF96"
        case .border:
            return "#3A3A3A"
        case .primaryText:
            return "#F2F2F2"
        case .secondaryText:
            return "#AEAEAE"
        case .tertiaryText:
            return "#707070"
        case .disabledText:
            return "#696969"
        case .accent:
            return "#FFAD56"
        case .accentHover:
            return "#FFC247"
        case .accentPressed:
            return "#D99100"
        case .statusButtonFill:
            return "#202020"
        case .statusButtonCriticalFill:
            return "#D00000"
        case .statusButtonAttentionFill:
            return "#C8D300"
        case .valueSliderFill:
            return "#00AFC8"
        case .waveformBackground:
            return "#A9A9A9"
        case .waveformColor:
            return "#212121"
        case .waveformDisabledBackground:
            return "#5C5C5C"
        case .waveformDisabledColor:
            return "#2F2F2F"
        case .harmonyTrackBackground:
            return "#D8D0BE"
        case .timeTrackAccentBeatLine:
            return "#747474"
        case .timeTrackBeatLine:
            return "#AEAEAE"
        case .waveformAccentBeatLine:
            return "#0C0C0C"
        case .waveformBeatLine:
            return "#0C0C0C"
        }
    }
}

enum AppColorRoleGroup: String, CaseIterable, Identifiable {
    case backgrounds
    case text
    case controls
    case accentStatus
    case waveform
    case timeline
    case gridLines

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backgrounds:
            return "Backgrounds"
        case .text:
            return "Text"
        case .controls:
            return "Controls"
        case .accentStatus:
            return "Accent & Status"
        case .waveform:
            return "Waveform"
        case .timeline:
            return "Timeline"
        case .gridLines:
            return "Grid Lines"
        }
    }

    var roles: [AppColorRole] {
        switch self {
        case .backgrounds:
            return [.appBackground, .panelBackground, .elevatedSurface]
        case .text:
            return [.primaryText, .secondaryText, .tertiaryText, .disabledText]
        case .controls:
            return [.controlBackground, .controlHover, .controlActive, .loopButtonActive, .border, .valueSliderFill]
        case .accentStatus:
            return [.accent, .accentHover, .accentPressed, .statusButtonFill, .statusButtonCriticalFill, .statusButtonAttentionFill]
        case .waveform:
            return [.waveformBackground, .waveformColor, .waveformDisabledBackground, .waveformDisabledColor]
        case .timeline:
            return [.harmonyTrackBackground]
        case .gridLines:
            return [.timeTrackAccentBeatLine, .timeTrackBeatLine, .waveformAccentBeatLine, .waveformBeatLine]
        }
    }
}

struct AppColorPalette: Codable, Equatable {
    static let defaultValue = AppColorPalette(
        values: Dictionary(uniqueKeysWithValues: AppColorRole.allCases.map { ($0.rawValue, $0.defaultHex) })
    )

    private var values: [String: String]

    init(values: [String: String] = [:]) {
        self.values = values
    }

    func hex(for role: AppColorRole) -> String {
        Self.normalizedHex(values[role.rawValue] ?? role.defaultHex) ?? role.defaultHex
    }

    func updating(_ role: AppColorRole, hex: String) -> AppColorPalette {
        var copy = self
        copy.values[role.rawValue] = Self.normalizedHex(hex) ?? role.defaultHex
        return copy
    }

    func normalized() -> AppColorPalette {
        AppColorPalette(
            values: Dictionary(uniqueKeysWithValues: AppColorRole.allCases.map { ($0.rawValue, hex(for: $0)) })
        )
    }

    static func normalizedHex(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard raw.count == 6, raw.allSatisfy(\.isHexDigit) else { return nil }
        return "#\(raw.uppercased())"
    }
}

final class AppSettingsStore: ObservableObject {
    static let clickSoundSettingsKey = "click.soundSettings"
    static let stemBackendComputeModeKey = "stemBackend.computeMode"
    static let colorPaletteKey = "theme.colorPalette"
    static let audioDeviceSettingsKey = "audio.deviceSettings"

    private let defaults: UserDefaults

    @Published private(set) var clickSoundSettings: ClickSoundSettings
    @Published private(set) var stemBackendComputeMode: StemBackendComputeMode
    @Published private(set) var colorPalette: AppColorPalette
    @Published private(set) var audioDeviceSettings: AudioDeviceSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.clickSoundSettings = Self.restoreClickSoundSettings(from: defaults)
        self.stemBackendComputeMode = Self.restoreStemBackendComputeMode(from: defaults)
        self.colorPalette = Self.restoreColorPalette(from: defaults)
        self.audioDeviceSettings = Self.restoreAudioDeviceSettings(from: defaults)
    }

    func updateClickSoundSettings(_ settings: ClickSoundSettings) {
        clickSoundSettings = settings.clamped()
        persistClickSoundSettings()
    }

    func updateStemBackendComputeMode(_ mode: StemBackendComputeMode) {
        stemBackendComputeMode = mode
        defaults.set(mode.rawValue, forKey: Self.stemBackendComputeModeKey)
    }

    func resetClickSoundSettingsToDefaults() {
        updateClickSoundSettings(.defaultValue)
    }

    func updateColor(_ role: AppColorRole, hex: String) {
        colorPalette = colorPalette.updating(role, hex: hex).normalized()
        persistColorPalette()
    }

    func resetColorPaletteToDefaults() {
        colorPalette = .defaultValue
        persistColorPalette()
    }

    func updateAudioInputDeviceUID(_ uid: String?) {
        audioDeviceSettings = AudioDeviceSettings(
            inputDeviceUID: uid,
            outputDeviceUID: audioDeviceSettings.outputDeviceUID
        ).normalized()
        persistAudioDeviceSettings()
    }

    func updateAudioOutputDeviceUID(_ uid: String?) {
        audioDeviceSettings = AudioDeviceSettings(
            inputDeviceUID: audioDeviceSettings.inputDeviceUID,
            outputDeviceUID: uid
        ).normalized()
        persistAudioDeviceSettings()
    }

    func resetAudioDevicesToSystemDefault() {
        audioDeviceSettings = .defaultValue
        persistAudioDeviceSettings()
    }

    private func persistClickSoundSettings() {
        guard let data = try? JSONEncoder().encode(clickSoundSettings.clamped()) else { return }
        defaults.set(data, forKey: Self.clickSoundSettingsKey)
    }

    private static func restoreClickSoundSettings(from defaults: UserDefaults) -> ClickSoundSettings {
        guard
            let data = defaults.data(forKey: clickSoundSettingsKey),
            let settings = try? JSONDecoder().decode(ClickSoundSettings.self, from: data)
        else {
            return .defaultValue
        }

        return settings.clamped()
    }

    private static func restoreStemBackendComputeMode(from defaults: UserDefaults) -> StemBackendComputeMode {
        guard
            let rawValue = defaults.string(forKey: stemBackendComputeModeKey),
            let mode = StemBackendComputeMode(rawValue: rawValue)
        else {
            return .cpuOnly
        }

        return mode
    }

    private func persistColorPalette() {
        guard let data = try? JSONEncoder().encode(colorPalette.normalized()) else { return }
        defaults.set(data, forKey: Self.colorPaletteKey)
    }

    private static func restoreColorPalette(from defaults: UserDefaults) -> AppColorPalette {
        guard
            let data = defaults.data(forKey: colorPaletteKey),
            let palette = try? JSONDecoder().decode(AppColorPalette.self, from: data)
        else {
            return .defaultValue
        }

        return palette.normalized()
    }

    private func persistAudioDeviceSettings() {
        guard let data = try? JSONEncoder().encode(audioDeviceSettings.normalized()) else { return }
        defaults.set(data, forKey: Self.audioDeviceSettingsKey)
    }

    private static func restoreAudioDeviceSettings(from defaults: UserDefaults) -> AudioDeviceSettings {
        guard
            let data = defaults.data(forKey: audioDeviceSettingsKey),
            let settings = try? JSONDecoder().decode(AudioDeviceSettings.self, from: data)
        else {
            return .defaultValue
        }

        return settings.normalized()
    }
}
