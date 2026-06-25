import AVFoundation
import AVKit
import AppKit
import Foundation

@MainActor
protocol VideoFollowerControlling: AnyObject {
    var isWindowOpen: Bool { get }
    var onWindowOpenChanged: ((Bool) -> Void)? { get set }

    func load(videoURL: URL?)
    func unload()
    func closeWindow()
    func showWindow(at time: TimeInterval, isPlaying: Bool, rate: Float)
    func toggleWindow(at time: TimeInterval, isPlaying: Bool, rate: Float)
    func play(rate: Float)
    func pause()
    func stop()
    func seek(to time: TimeInterval)
    func setPlaybackRate(_ rate: Float)
    func sync(to audioTime: TimeInterval, isPlaying: Bool, rate: Float)
}

@MainActor
final class VideoFollowerController: NSObject, VideoFollowerControlling, NSWindowDelegate {
    private let player = AVPlayer()
    private var window: NSWindow?
    private var playerView: AVPlayerView?
    private var currentVideoURL: URL?
    private let driftTolerance: TimeInterval
    var onWindowOpenChanged: ((Bool) -> Void)?

    var isWindowOpen: Bool {
        window != nil
    }

    init(driftTolerance: TimeInterval = 0.2) {
        self.driftTolerance = driftTolerance
        super.init()
        player.isMuted = true
    }

    func load(videoURL: URL?) {
        guard let videoURL else {
            unload()
            return
        }

        if currentVideoURL != videoURL {
            currentVideoURL = videoURL
            player.replaceCurrentItem(with: AVPlayerItem(url: videoURL))
            player.isMuted = true
        }
    }

    func unload() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentVideoURL = nil
        closeWindow()
    }

    func closeWindow() {
        window?.close()
    }

    func play(rate: Float) {
        guard currentVideoURL != nil, window != nil else { return }
        player.playImmediately(atRate: normalizedRate(rate))
    }

    func pause() {
        player.pause()
    }

    func stop() {
        player.pause()
        seek(to: 0)
    }

    func seek(to time: TimeInterval) {
        guard currentVideoURL != nil else { return }
        player.seek(to: cmTime(for: time), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setPlaybackRate(_ rate: Float) {
        guard window != nil, player.rate != 0 else { return }
        player.rate = normalizedRate(rate)
    }

    func sync(to audioTime: TimeInterval, isPlaying: Bool, rate: Float) {
        guard currentVideoURL != nil, window != nil else { return }

        let videoTime = player.currentTime().seconds
        if videoTime.isFinite, abs(videoTime - audioTime) > driftTolerance {
            seek(to: audioTime)
        }

        if isPlaying {
            if player.rate == 0 {
                player.playImmediately(atRate: normalizedRate(rate))
            } else {
                player.rate = normalizedRate(rate)
            }
        } else if player.rate != 0 {
            player.pause()
        }
    }

    func windowWillClose(_ notification: Notification) {
        player.pause()
        guard window != nil else { return }

        window = nil
        playerView = nil
        onWindowOpenChanged?(false)
    }

    func showWindow(at time: TimeInterval, isPlaying: Bool, rate: Float) {
        guard currentVideoURL != nil else { return }
        showWindow()
        seek(to: time)
        if isPlaying {
            player.playImmediately(atRate: normalizedRate(rate))
        } else {
            player.pause()
        }
    }

    func toggleWindow(at time: TimeInterval, isPlaying: Bool, rate: Float) {
        guard currentVideoURL != nil else { return }

        if window != nil {
            window?.close()
            return
        }

        showWindow(at: time, isPlaying: isPlaying, rate: rate)
    }

    private func showWindow() {
        let wasOpen = window != nil

        if window == nil {
            let view = AVPlayerView(frame: NSRect(x: 0, y: 0, width: 720, height: 405))
            view.player = player
            view.controlsStyle = .none
            playerView = view

            let window = NSWindow(
                contentRect: view.frame,
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Video"
            window.contentView = view
            window.delegate = self
            window.isReleasedWhenClosed = false
            self.window = window
        }

        window?.makeKeyAndOrderFront(nil)

        if !wasOpen {
            onWindowOpenChanged?(true)
        }
    }

    private func normalizedRate(_ rate: Float) -> Float {
        ProjectStateNormalizer.normalizedPlaybackRate(rate)
    }

    private func cmTime(for seconds: TimeInterval) -> CMTime {
        CMTime(seconds: max(0, seconds), preferredTimescale: 600)
    }
}
