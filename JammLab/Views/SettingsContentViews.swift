import AppKit
import SwiftUI

struct ThemeColorsSettingsContentView: View {
    @ObservedObject var settingsStore: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            ForEach(Array(AppColorRoleGroup.allCases.enumerated()), id: \.element.id) { index, group in
                ThemeColorGroupSection(
                    group: group,
                    showsDivider: index > 0,
                    settingsStore: settingsStore,
                    colorBinding: colorBinding(for:)
                )
            }

            Button("Reset Theme Colors") {
                settingsStore.resetColorPaletteToDefaults()
            }
            .help(ControlHelpText.resetThemeColors)
            .padding(.top, AppTheme.Spacing.xs)
        }
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    private func colorBinding(for role: AppColorRole) -> Binding<Color> {
        Binding(
            get: {
                AppThemeColors(palette: settingsStore.colorPalette).color(for: role)
            },
            set: { color in
                settingsStore.updateColor(role, hex: Self.hexString(from: color))
            }
        )
    }

    private static func hexString(from color: Color) -> String {
        let nsColor = NSColor(color)
        let rgbColor = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        let red = Int((rgbColor.redComponent * 255).rounded())
        let green = Int((rgbColor.greenComponent * 255).rounded())
        let blue = Int((rgbColor.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

private struct ThemeColorGroupSection: View {
    let group: AppColorRoleGroup
    let showsDivider: Bool
    @ObservedObject var settingsStore: AppSettingsStore
    let colorBinding: (AppColorRole) -> Binding<Color>

    @Environment(\.appColors) private var appColors

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            if showsDivider {
                Rectangle()
                    .fill(appColors.border)
                    .frame(height: AppTheme.Stroke.thin)
                    .padding(.bottom, AppTheme.Spacing.xs)
            }

            Text(group.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(appColors.secondaryText)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                ForEach(group.roles) { role in
                    ThemeColorSettingRow(
                        role: role,
                        hexValue: settingsStore.colorPalette.hex(for: role),
                        color: colorBinding(role)
                    )
                }
            }
        }
    }
}

private struct ThemeColorSettingRow: View {
    let role: AppColorRole
    let hexValue: String
    let color: Binding<Color>

    @Environment(\.appColors) private var appColors

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Text(role.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(appColors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            ColorPicker(
                "",
                selection: color,
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: 32)

            Text(hexValue)
                .font(AppTheme.Typography.captionMonospaced)
                .foregroundStyle(appColors.secondaryText)
                .frame(width: 72, alignment: .trailing)
        }
    }
}

struct ClickSettingsContentView: View {
    @ObservedObject var settingsStore: AppSettingsStore
    let clickSoundBinding: (WritableKeyPath<ClickSoundSettings, Double>) -> Binding<Double>
    @Environment(\.appColors) private var appColors

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            clickSettingStepper(
                title: "Accent frequency",
                value: clickSoundBinding(\.accentFrequencyHz),
                range: ClickSoundSettings.frequencyRange,
                step: 10,
                unit: "Hz"
            )

            clickSettingStepper(
                title: "Regular frequency",
                value: clickSoundBinding(\.regularFrequencyHz),
                range: ClickSoundSettings.frequencyRange,
                step: 10,
                unit: "Hz"
            )

            clickSettingStepper(
                title: "Accent length",
                value: clickSoundBinding(\.accentLengthMs),
                range: ClickSoundSettings.lengthRange,
                step: 1,
                unit: "ms"
            )

            clickSettingStepper(
                title: "Regular length",
                value: clickSoundBinding(\.regularLengthMs),
                range: ClickSoundSettings.lengthRange,
                step: 1,
                unit: "ms"
            )

            Button("Reset Click Defaults") {
                settingsStore.resetClickSoundSettingsToDefaults()
            }
            .help(ControlHelpText.resetClickDefaults)
            .padding(.top, AppTheme.Spacing.xs)
        }
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    private func clickSettingStepper(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String
    ) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer()
            Stepper(value: value, in: range, step: step) {
                Text("\(Int(value.wrappedValue.rounded())) \(unit)")
                    .foregroundStyle(appColors.secondaryText)
                    .frame(width: 84, alignment: .trailing)
            }
        }
    }
}

struct StemBackendSettingsContentView: View {
    let stemBackendComputeModeBinding: Binding<StemBackendComputeMode>
    @Environment(\.appColors) private var appColors

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Picker("Compute mode", selection: stemBackendComputeModeBinding) {
                ForEach(StemBackendComputeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text("CPU Only is the stable default. Auto allows the bundled separator to use available acceleration.")
                .font(.caption)
                .foregroundStyle(appColors.secondaryText)
        }
        .padding(.vertical, AppTheme.Spacing.sm)
    }
}

struct AudioSettingsContentView: View {
    @ObservedObject var settingsStore: AppSettingsStore

    @State private var inputDevices: [AudioDeviceInfo] = []
    @State private var outputDevices: [AudioDeviceInfo] = []
    @State private var inputPermissionStatus = SystemAudioInputPermissionProvider().authorizationStatus
    @State private var errorText: String?

    private let deviceLoader = AudioSettingsDeviceLoader()

    @Environment(\.appColors) private var appColors

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                devicePicker(
                    title: "Audio Input Device",
                    selection: inputSelectionBinding,
                    devices: inputDevices,
                    selectedUID: settingsStore.audioDeviceSettings.inputDeviceUID
                )

                devicePicker(
                    title: "Audio Output Device",
                    selection: outputSelectionBinding,
                    devices: outputDevices,
                    selectedUID: settingsStore.audioDeviceSettings.outputDeviceUID
                )
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                Button("Refresh Devices") {
                    refreshDevices()
                }
                .help(ControlHelpText.refreshAudioDevices)

                Button("Reset to System Default") {
                    settingsStore.resetAudioDevicesToSystemDefault()
                }
                .help(ControlHelpText.resetAudioDevices)
            }

            Text(inputPermissionText)
                .font(.caption)
                .foregroundStyle(appColors.secondaryText)

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .onAppear(perform: refreshDevices)
    }

    private var inputSelectionBinding: Binding<String?> {
        Binding(
            get: { settingsStore.audioDeviceSettings.inputDeviceUID },
            set: { settingsStore.updateAudioInputDeviceUID($0) }
        )
    }

    private var outputSelectionBinding: Binding<String?> {
        Binding(
            get: { settingsStore.audioDeviceSettings.outputDeviceUID },
            set: { settingsStore.updateAudioOutputDeviceUID($0) }
        )
    }

    private func devicePicker(
        title: String,
        selection: Binding<String?>,
        devices: [AudioDeviceInfo],
        selectedUID: String?
    ) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(appColors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker(title, selection: selection) {
                Text("System Default")
                    .tag(Optional<String>.none)

                ForEach(devices) { device in
                    Text(deviceTitle(device))
                        .tag(Optional(device.uid))
                }

                if let selectedUID,
                   !devices.contains(where: { $0.uid == selectedUID }) {
                    Text("Unavailable: \(selectedUID)")
                        .tag(Optional(selectedUID))
                }
            }
            .labelsHidden()
            .frame(width: 260)
            .help(title)
        }
    }

    private func deviceTitle(_ device: AudioDeviceInfo) -> String {
        device.isDefault ? "\(device.name) (Default)" : device.name
    }

    private var inputPermissionText: String {
        switch inputPermissionStatus {
        case .authorized:
            return "Input device is used by the tuner. Output changes apply to playback immediately."
        case .notDetermined:
            return "Input devices will be listed after opening the tuner. Output changes apply to playback immediately."
        case .denied:
            return "Audio input access is disabled. Output changes apply to playback immediately."
        }
    }

    private func refreshDevices() {
        let result = deviceLoader.refreshDevices()
        inputDevices = result.inputDevices
        outputDevices = result.outputDevices
        inputPermissionStatus = result.inputPermissionStatus
        errorText = result.errorText
    }
}

struct AudioSettingsDeviceRefreshResult: Equatable {
    let inputDevices: [AudioDeviceInfo]
    let outputDevices: [AudioDeviceInfo]
    let inputPermissionStatus: AudioInputPermissionStatus
    let errorText: String?
}

struct AudioSettingsDeviceLoader {
    var deviceProvider: AudioDeviceProviding = AudioDeviceService()
    var inputPermissionProvider: AudioInputPermissionProviding = SystemAudioInputPermissionProvider()

    func refreshDevices() -> AudioSettingsDeviceRefreshResult {
        var inputDevices: [AudioDeviceInfo] = []
        var outputDevices: [AudioDeviceInfo] = []
        var errors: [String] = []

        do {
            outputDevices = try deviceProvider.outputDevices()
        } catch {
            errors.append(error.localizedDescription)
        }

        let inputPermissionStatus = inputPermissionProvider.authorizationStatus
        if inputPermissionStatus == .authorized {
            do {
                inputDevices = try deviceProvider.inputDevices()
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        return AudioSettingsDeviceRefreshResult(
            inputDevices: inputDevices,
            outputDevices: outputDevices,
            inputPermissionStatus: inputPermissionStatus,
            errorText: errors.isEmpty ? nil : errors.joined(separator: "\n")
        )
    }
}
