import SwiftUI

struct InspectorSidebarView: View {
    @Binding var selectedFilter: NotesFilter
    let notes: [TimecodedNote]
    let selectedRegionID: TimecodedNote.ID?
    let onSelect: (TimecodedNote) -> Void
    let onEdit: (TimecodedNote) -> Void
    let onDelete: (TimecodedNote.ID) -> Void
    let onColorChanged: (TimecodedNote.ID, MarkerColor) -> Void
    let onCustomColorChanged: (TimecodedNote.ID, String) -> Void
    @Environment(\.appColors) private var appColors

    private var filteredNotes: [TimecodedNote] {
        switch selectedFilter {
        case .notes:
            return notes
        case .markers:
            return notes.filter(\.isMarker)
        case .regions:
            return notes.filter(\.isRegion)
        }
    }

    var body: some View {
        AppPanel {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                HStack {
                    AppSectionTitle(title: "Inspector")

                    Spacer()

                    Text("\(filteredNotes.count)")
                        .font(AppTheme.Typography.badge)
                        .foregroundStyle(appColors.secondaryText)
                }

                Picker("Inspector Filter", selection: $selectedFilter) {
                    ForEach(NotesFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)

                if filteredNotes.isEmpty {
                    Text(emptyText)
                        .font(.subheadline)
                        .foregroundStyle(appColors.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: AppTheme.ControlSize.notesEmptyMinHeight, alignment: .topLeading)
                        .padding(AppTheme.Spacing.xl)
                        .background(appColors.controlBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.panel))
                } else {
                    ScrollView {
                        VStack(spacing: AppTheme.Spacing.md) {
                            ForEach(filteredNotes) { note in
                                Button {
                                    onSelect(note)
                                } label: {
                                    NoteRowView(
                                        note: note,
                                        isSelected: note.id == selectedRegionID,
                                        timeText: noteTimeText(note)
                                    )
                                }
                                .buttonStyle(.plain)
                                .overlay(noteContextMenuCapture(note))
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .frame(width: AppTheme.ControlSize.inspectorSidebarWidth, alignment: .topLeading)
    }

    private var emptyText: String {
        switch selectedFilter {
        case .notes:
            return "Right-click waveform or press M"
        case .markers:
            return "No markers yet"
        case .regions:
            return "No regions yet"
        }
    }

    private func noteContextMenuCapture(_ note: TimecodedNote) -> some View {
        NoteContextMenuCaptureView(
            note: note,
            onEdit: onEdit,
            onDelete: onDelete,
            onColorChanged: onColorChanged,
            onCustomColorChanged: onCustomColorChanged
        )
    }

    private func noteTimeText(_ note: TimecodedNote) -> String {
        if note.isRegion {
            return "\(TimeFormatter.mmssTenths(note.time)) - \(TimeFormatter.mmssTenths(note.regionEndTime))"
        }

        return TimeFormatter.mmssTenths(note.time)
    }
}
