import SwiftUI

struct AppUpdateHostModifier: ViewModifier {
    let coordinator: AppUpdateCoordinator

    @State private var presentedRelease: AppRelease?

    func body(content: Content) -> some View {
        content
            .task {
                presentedRelease = await coordinator.checkAtLaunch()
            }
            .sheet(item: $presentedRelease) { release in
                UpdateAvailableView(
                    currentVersion: coordinator.currentVersion,
                    release: release,
                    isSkippingVersion: Binding(
                        get: { coordinator.isSkipping(release) },
                        set: { coordinator.setSkipping($0, release: release) }
                    ),
                    onDismiss: {
                        presentedRelease = nil
                    }
                )
            }
    }
}

extension View {
    func appUpdateCheckHost(coordinator: AppUpdateCoordinator) -> some View {
        modifier(AppUpdateHostModifier(coordinator: coordinator))
    }
}

struct UpdateAvailableView: View {
    let currentVersion: AppVersion?
    let release: AppRelease
    @Binding var isSkippingVersion: Bool
    let onDismiss: () -> Void
    private let releaseNotes: AttributedString

    @Environment(\.appColors) private var appColors
    @Environment(\.openURL) private var openURL

    init(
        currentVersion: AppVersion?,
        release: AppRelease,
        isSkippingVersion: Binding<Bool>,
        onDismiss: @escaping () -> Void
    ) {
        self.currentVersion = currentVersion
        self.release = release
        _isSkippingVersion = isSkippingVersion
        self.onDismiss = onDismiss

        let source = release.notes.isEmpty
            ? "Release notes are available on GitHub."
            : release.notes
        releaseNotes = AppReleaseNotesFormatter.nonInteractiveMarkdown(source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sectionGap) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("A New Version Is Available")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(appColors.primaryText)

                Text(versionSummary)
                    .font(.body)
                    .foregroundStyle(appColors.secondaryText)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text(release.title)
                    .font(AppTheme.Typography.sectionTitle)
                    .foregroundStyle(appColors.primaryText)

                ScrollView {
                    Text(releaseNotes)
                        .font(.body)
                        .foregroundStyle(appColors.secondaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.Spacing.panelPadding)
                }
                .frame(height: AppTheme.Window.updateReleaseNotesHeight)
                .background(appColors.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
            }

            Toggle("Skip This Version", isOn: $isSkippingVersion)
                .foregroundStyle(appColors.primaryText)
                .help("Do not show this update again. A newer release will still be shown.")
                .accessibilityLabel("Skip this version")
                .accessibilityValue(isSkippingVersion ? "Enabled" : "Disabled")

            HStack(spacing: AppTheme.Spacing.md) {
                Spacer()

                Button("Remind Me Later") {
                    onDismiss()
                }
                .help("Close this message and show it again the next time JammLab launches.")
                .accessibilityLabel("Remind me later")

                Button("Download on GitHub") {
                    openURL(release.pageURL)
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .help("Open the JammLab release page in your web browser.")
                .accessibilityLabel("Download JammLab \(release.version.description) on GitHub")
            }
        }
        .padding(AppTheme.Spacing.windowPadding)
        .frame(width: AppTheme.Window.updateSheetWidth)
        .background(appColors.panelBackground)
    }

    private var versionSummary: String {
        let installedVersion = currentVersion?.description ?? "Unknown"
        return "Installed: \(installedVersion)  •  Available: \(release.version.description)"
    }
}

enum AppReleaseNotesFormatter {
    static func nonInteractiveMarkdown(_ source: String) -> AttributedString {
        guard var attributed = try? AttributedString(markdown: source) else {
            return AttributedString(source)
        }

        let linkRanges = attributed.runs.compactMap { run in
            run.link == nil ? nil : run.range
        }
        for range in linkRanges {
            attributed[range].link = nil
        }
        return attributed
    }
}
