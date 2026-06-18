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
