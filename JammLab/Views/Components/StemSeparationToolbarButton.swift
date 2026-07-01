import SwiftUI

struct StemSeparationToolbarButton: View {
    let hasAudio: Bool
    let separationState: StemSeparationViewState
    let onSeparate: (StemSeparationMethod) -> Void
    let onCancel: () -> Void
    @State private var isMethodSheetPresented = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if separationState.isProcessing {
                Button(role: .cancel) {
                    onCancel()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .help(ControlHelpText.cancelStemSeparation)

                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    isMethodSheetPresented = true
                } label: {
                    Label("Separate Stems", systemImage: "waveform.badge.magnifyingglass")
                }
                .disabled(!hasAudio)
                .help(ControlHelpText.separateStems)
                .sheet(isPresented: $isMethodSheetPresented) {
                    StemSeparationMethodSelectionSheet { method in
                        isMethodSheetPresented = false
                        onSeparate(method)
                    } onCancel: {
                        isMethodSheetPresented = false
                    }
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

private struct StemSeparationMethodSelectionSheet: View {
    let onSelect: (StemSeparationMethod) -> Void
    let onCancel: () -> Void
    @Environment(\.appColors) private var appColors
    @State private var selectedMethodID = StemSeparationMethod.defaultValue.id

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("Separate Stems")
                .font(AppTheme.Typography.sectionTitle)
                .foregroundStyle(appColors.primaryText)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                ForEach(StemSeparationMethod.allCases) { method in
                    StemSeparationMethodOptionRow(
                        method: method,
                        isSelected: selectedMethodID == method.id
                    ) {
                        selectedMethodID = method.id
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Stem separation method")

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Separate") {
                    onSelect(selectedMethod)
                }
                .keyboardShortcut(.defaultAction)
                .help("Start stem separation with the selected method")
            }
        }
        .padding(AppTheme.Spacing.xl)
        .frame(width: 420)
        .background(appColors.panelBackground)
    }

    private var selectedMethod: StemSeparationMethod {
        StemSeparationMethod.method(forID: selectedMethodID) ?? .defaultValue
    }
}

private struct StemSeparationMethodOptionRow: View {
    let method: StemSeparationMethod
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(\.appColors) private var appColors

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? appColors.accent : appColors.secondaryText)
                    .frame(width: 18, height: 18)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(method.title)
                        .font(AppTheme.Typography.noteTitle)
                        .foregroundStyle(appColors.primaryText)
                    Text(method.optionDescription)
                        .font(.caption)
                        .foregroundStyle(appColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.md)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .background(isSelected ? appColors.controlActive : appColors.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                .stroke(isSelected ? appColors.accent : appColors.border, lineWidth: AppTheme.Stroke.thin)
        }
        .help("Select \(method.title)")
        .accessibilityLabel(method.title)
        .accessibilityValue(isSelected ? "Selected. \(method.optionDescription)" : method.optionDescription)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
