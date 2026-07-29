import SwiftUI

struct AudioPreparationCard: View {
    let state: AudioPreparationViewState
    let onCancel: () -> Void

    var body: some View {
        AppPanel {
            HStack(spacing: AppTheme.Spacing.md) {
                progressIndicator

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    AppSectionTitle(title: title)
                    Text(state.status)
                        .font(AppTheme.Typography.tileTitle)
                        .lineLimit(2)
                }

                Spacer(minLength: AppTheme.Spacing.md)

                if state.isCancellable {
                    Button("Cancel", role: .cancel, action: onCancel)
                        .help("Cancel audio preparation")
                        .accessibilityLabel("Cancel audio preparation")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(state.status)
    }

    @ViewBuilder
    private var progressIndicator: some View {
        if let progress = state.progress {
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .accessibilityValue("\(Int((progress * 100).rounded())) percent")
        } else {
            ProgressView()
                .progressViewStyle(.circular)
        }
    }

    private var title: String {
        switch state.kind {
        case .importing:
            return "Importing Audio"
        case .openingProject:
            return "Opening Project"
        case .switchingMode:
            return "Preparing Playback"
        case nil:
            return "Preparing Audio"
        }
    }
}
