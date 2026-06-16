import SwiftUI

struct NoteRowView: View {
    let note: TimecodedNote
    let isSelected: Bool
    let timeText: String
    @Environment(\.appColors) private var appColors

    var body: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: iconName)
                .foregroundStyle(note.resolvedSwiftUIColor)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxxs) {
                Text(note.title)
                    .font(AppTheme.Typography.noteTitle)
                    .foregroundStyle(appColors.primaryText)
                Text(timeText)
                    .font(AppTheme.Typography.captionMonospaced)
                    .foregroundStyle(appColors.secondaryText)
            }

            Spacer()
        }
        .padding(AppTheme.Spacing.lg)
        .background(isSelected ? note.resolvedSwiftUIColor.opacity(AppTheme.Timeline.selectedNoteBackgroundOpacity) : appColors.controlBackground)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.panel)
                .stroke(isSelected ? note.resolvedSwiftUIColor.opacity(AppTheme.Timeline.selectedNoteStrokeOpacity) : Color.clear, lineWidth: AppTheme.Stroke.thin)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.panel))
    }

    private var iconName: String {
        if note.isRegion {
            return "rectangle.dashed"
        }
        if note.isTempoTimeSignatureMarker {
            return "metronome"
        }
        return "bookmark.fill"
    }
}
