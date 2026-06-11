import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @State private var selectedSection: SettingsSection = .general
    @Environment(\.appColors) private var appColors

    var body: some View {
        HStack(spacing: AppTheme.Spacing.none) {
            SettingsSidebarView(selectedSection: $selectedSection)

            Rectangle()
                .fill(AppTheme.Settings.dividerColor)
                .frame(width: AppTheme.Stroke.thin)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sectionGap) {
                SettingsDetailHeader(section: selectedSection)

                ScrollView {
                    Group {
                        switch selectedSection {
                        case .general:
                            GeneralSettingsContentView()
                        case .themeColors:
                            ThemeColorsSettingsContentView(settingsStore: settingsStore)
                        case .click:
                            ClickSettingsContentView(
                                settingsStore: settingsStore,
                                clickSoundBinding: clickSoundBinding
                            )
                        case .audio:
                            AudioSettingsContentView(settingsStore: settingsStore)
                        case .stemBackend:
                            StemBackendSettingsContentView(
                                stemBackendComputeModeBinding: stemBackendComputeModeBinding
                            )
                        }
                    }
                    .frame(maxWidth: AppTheme.Settings.detailContentWidth, alignment: .leading)
                }

                Spacer(minLength: AppTheme.Spacing.none)
            }
            .padding(AppTheme.Settings.detailPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(appColors.appBackground)
        }
        .frame(width: AppTheme.Settings.windowWidth)
        .frame(minHeight: AppTheme.Settings.windowMinHeight)
        .background(appColors.appBackground)
    }

    private func clickSoundBinding(_ keyPath: WritableKeyPath<ClickSoundSettings, Double>) -> Binding<Double> {
        Binding(
            get: { settingsStore.clickSoundSettings[keyPath: keyPath] },
            set: { newValue in
                var settings = settingsStore.clickSoundSettings
                settings[keyPath: keyPath] = newValue
                settingsStore.updateClickSoundSettings(settings)
            }
        )
    }

    private var stemBackendComputeModeBinding: Binding<StemBackendComputeMode> {
        Binding(
            get: { settingsStore.stemBackendComputeMode },
            set: { settingsStore.updateStemBackendComputeMode($0) }
        )
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case themeColors
    case click
    case audio
    case stemBackend

    var id: Self { self }

    var title: String {
        switch self {
        case .general:
            "General"
        case .themeColors:
            "Theme & Colors"
        case .click:
            "Click"
        case .audio:
            "Audio"
        case .stemBackend:
            "Stem Backend"
        }
    }
}

private struct SettingsSidebarView: View {
    @Binding var selectedSection: SettingsSection
    @Environment(\.appColors) private var appColors

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
            ForEach(SettingsSection.allCases) { section in
                SettingsSidebarRow(
                    section: section,
                    isSelected: selectedSection == section
                ) {
                    selectedSection = section
                }
            }

            Spacer(minLength: AppTheme.Spacing.none)
        }
        .padding(.top, AppTheme.Spacing.xl)
        .padding(.horizontal, AppTheme.Spacing.xs)
        .frame(width: AppTheme.Settings.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(appColors.panelBackground)
    }
}

private struct SettingsSidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.appColors) private var appColors

    var body: some View {
        Button(action: action) {
            Text(section.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? appColors.primaryText : appColors.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: AppTheme.Settings.rowHeight, alignment: .leading)
                .padding(.horizontal, AppTheme.Spacing.md)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
        .onHover { isHovered = $0 }
        .accessibilityLabel(section.title)
    }

    private var rowBackground: Color {
        if isSelected {
            appColors.elevatedSurface
        } else if isHovered {
            appColors.controlHover
        } else {
            .clear
        }
    }
}

private struct SettingsDetailHeader: View {
    let section: SettingsSection
    @Environment(\.appColors) private var appColors

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text(section.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(appColors.primaryText)

            Rectangle()
                .fill(appColors.border)
                .frame(height: AppTheme.Stroke.thin)
        }
    }
}

private struct GeneralSettingsContentView: View {
    @Environment(\.appColors) private var appColors

    var body: some View {
        Text("No general settings yet.")
            .font(.caption)
            .foregroundStyle(appColors.secondaryText)
            .padding(.vertical, AppTheme.Spacing.sm)
    }
}

private struct ThemeColorsSettingsContentView: View {
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

private struct ClickSettingsContentView: View {
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

private struct StemBackendSettingsContentView: View {
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

private struct AudioSettingsContentView: View {
    @ObservedObject var settingsStore: AppSettingsStore

    @State private var inputDevices: [AudioDeviceInfo] = []
    @State private var outputDevices: [AudioDeviceInfo] = []
    @State private var errorText: String?

    private let deviceService = AudioDeviceService()

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

            Text("Input device is saved for future recording and monitoring. Output changes apply to playback immediately.")
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

    private func refreshDevices() {
        do {
            inputDevices = try deviceService.inputDevices()
            outputDevices = try deviceService.outputDevices()
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
