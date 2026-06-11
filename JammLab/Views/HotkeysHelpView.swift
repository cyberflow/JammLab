import SwiftUI

struct HotkeysHelpView: View {
    @Environment(\.appColors) private var appColors

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sectionGap) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Keyboard Shortcuts")
                    .font(.title2.weight(.semibold))
                Text("Playback and loop controls")
                    .foregroundStyle(appColors.secondaryText)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(AppHotkey.allCases, id: \.self) { hotkey in
                        hotkeyRow(hotkey)

                        if hotkey != AppHotkey.allCases.last {
                            Divider()
                        }
                    }
                }
                .background(appColors.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.panel))
            }
            .scrollIndicators(.automatic)

            Spacer(minLength: 0)
        }
        .padding(AppTheme.Spacing.windowPadding)
        .frame(width: AppTheme.Window.helpWidth, alignment: .topLeading)
        .frame(
            minHeight: AppTheme.Window.helpMinHeight,
            idealHeight: AppTheme.Window.helpHeight,
            maxHeight: AppTheme.Window.helpHeight,
            alignment: .topLeading
        )
    }

    private func hotkeyRow(_ hotkey: AppHotkey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.panelPadding) {
            Text(hotkey.key)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(appColors.primaryText)
                .frame(width: AppTheme.ControlSize.hotkeyKeyWidth, alignment: .center)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(appColors.appBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(hotkey.title)
                    .font(.headline)
                Text(hotkey.detail)
                    .font(.subheadline)
                    .foregroundStyle(appColors.secondaryText)
            }

            Spacer()
        }
        .padding(AppTheme.Spacing.xxl)
    }
}

#Preview {
    HotkeysHelpView()
}
