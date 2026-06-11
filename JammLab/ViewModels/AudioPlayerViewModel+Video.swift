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
}
