import Foundation

extension AudioPlayerViewModel {
    var canShowVideoWindow: Bool {
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
}
