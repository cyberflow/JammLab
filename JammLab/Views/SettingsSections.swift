import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
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

struct SettingsSidebarView: View {
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

struct SettingsDetailHeader: View {
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

struct GeneralSettingsContentView: View {
    @Environment(\.appColors) private var appColors

    var body: some View {
        Text("No general settings yet.")
            .font(.caption)
            .foregroundStyle(appColors.secondaryText)
            .padding(.vertical, AppTheme.Spacing.sm)
    }
}
