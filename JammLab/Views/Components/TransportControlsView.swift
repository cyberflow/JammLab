import SwiftUI

struct TransportControlsView: View {
    let playbackState: PlaybackState
    let isLooping: Bool
    let onGoToStart: () -> Void
    let onGoToEnd: () -> Void
    let onPlayStop: () -> Void
    let onPause: () -> Void
    let onLoopChanged: (Bool) -> Void
    @Environment(\.appColors) private var appColors

    var body: some View {
        HStack(spacing: AppTheme.TransportControls.groupSpacing) {
            HStack(spacing: AppTheme.TransportControls.segmentedSpacing) {
                TransportButton(type: .goToStart, action: onGoToStart)
                TransportButton(type: .goToEnd, action: onGoToEnd)
            }

            TransportButton(type: .playStop(isPlaying: playbackState == .playing), action: onPlayStop)

            TransportButton(type: .pause, action: onPause)
                .disabled(playbackState != .playing)

            TransportButton(type: .loop(isActive: isLooping)) {
                onLoopChanged(!isLooping)
            }
        }
        .padding(AppTheme.TransportControls.groupPadding)
        .background {
            RoundedRectangle(cornerRadius: AppTheme.TransportControls.groupRadius, style: .continuous)
                .fill(groupGradient)
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.TransportControls.groupRadius, style: .continuous)
                        .stroke(appColors.border, lineWidth: AppTheme.TransportControls.groupBorderWidth)
                }
                .shadow(color: .black.opacity(0.32), radius: 3, x: 0, y: 1)
        }
        .fixedSize()
    }

    private var groupGradient: LinearGradient {
        LinearGradient(
            colors: [
                appColors.elevatedSurface,
                appColors.panelBackground
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

#Preview("Transport Controls") {
    VStack(alignment: .leading, spacing: 18) {
        TransportControlsView(
            playbackState: .stopped,
            isLooping: false,
            onGoToStart: {},
            onGoToEnd: {},
            onPlayStop: {},
            onPause: {},
            onLoopChanged: { _ in }
        )

        TransportControlsView(
            playbackState: .playing,
            isLooping: false,
            onGoToStart: {},
            onGoToEnd: {},
            onPlayStop: {},
            onPause: {},
            onLoopChanged: { _ in }
        )

        TransportControlsView(
            playbackState: .playing,
            isLooping: true,
            onGoToStart: {},
            onGoToEnd: {},
            onPlayStop: {},
            onPause: {},
            onLoopChanged: { _ in }
        )

        TransportControlsView(
            playbackState: .stopped,
            isLooping: false,
            onGoToStart: {},
            onGoToEnd: {},
            onPlayStop: {},
            onPause: {},
            onLoopChanged: { _ in }
        )
        .disabled(true)
    }
    .padding(24)
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Compact Toolbar") {
    TransportControlsView(
        playbackState: .stopped,
        isLooping: true,
        onGoToStart: {},
        onGoToEnd: {},
        onPlayStop: {},
        onPause: {},
        onLoopChanged: { _ in }
    )
    .padding(12)
    .background(Color.black.opacity(0.82))
}
