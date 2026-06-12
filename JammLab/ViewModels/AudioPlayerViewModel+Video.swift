import Foundation

extension AudioPlayerViewModel {
    var canShowVideoWindow: Bool {
        canToggleVideoWindow
    }

    var canToggleVideoWindow: Bool {
        importedFile?.mediaKind == .video
    }

    func showVideoWindow() {
        guard canShowVideoWindow else { return }
        videoFollower.showWindow(
            at: currentTime,
            isPlaying: playbackState == .playing,
            rate: playbackRate
        )
    }

    func toggleVideoWindow() {
        guard canToggleVideoWindow else { return }
        videoFollower.toggleWindow(
            at: currentTime,
            isPlaying: playbackState == .playing,
            rate: playbackRate
        )
    }

    func restoreVideoWindowOpenState(_ shouldOpen: Bool) {
        performWithoutVideoWindowDirtyTracking {
            if shouldOpen, canShowVideoWindow {
                videoFollower.showWindow(
                    at: currentTime,
                    isPlaying: playbackState == .playing,
                    rate: playbackRate
                )
            } else {
                videoFollower.closeWindow()
            }
        }
    }

    func performWithoutVideoWindowDirtyTracking(_ action: () -> Void) {
        let wasRestoringVideoWindowState = isRestoringVideoWindowState
        isRestoringVideoWindowState = true
        action()
        isVideoWindowOpen = videoFollower.isWindowOpen
        isRestoringVideoWindowState = wasRestoringVideoWindowState
    }

    func handleVideoWindowOpenChanged(_ isOpen: Bool) {
        guard isVideoWindowOpen != isOpen else { return }

        isVideoWindowOpen = isOpen
        guard !isRestoringVideoWindowState else { return }

        refreshProjectModifiedState()
    }
}
