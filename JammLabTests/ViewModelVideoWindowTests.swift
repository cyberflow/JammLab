import XCTest
@testable import JammLab

final class ViewModelVideoWindowTests: XCTestCase {
    @MainActor
    func testViewModelForwardsTransportCommandsToVideoFollower() throws {
        let engine = MockPlaybackEngine()
        engine.isLoaded = true
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine, videoFollower: videoFollower)
        viewModel.duration = 20

        viewModel.setPlaybackRate(0.5)
        viewModel.play()
        viewModel.seek(to: 10)
        viewModel.pause()
        viewModel.stop()

        XCTAssertEqual(try XCTUnwrap(videoFollower.playbackRate), 0.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(videoFollower.playRate), 0.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(videoFollower.seekTimes.last), 10, accuracy: 0.0001)
        XCTAssertTrue(videoFollower.didPause)
        XCTAssertTrue(videoFollower.didStop)
    }

    @MainActor
    func testVideoImportAutoShowsVideoWindowAndStartsClean() throws {
        let engine = MockPlaybackEngine()
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine, videoFollower: videoFollower)
        let audioURL = try temporaryAudioFile(duration: 2)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let videoURL = URL(fileURLWithPath: "/tmp/lesson.mov")
        let media = ImportedAudioFile(
            url: audioURL,
            sourceMediaURL: videoURL,
            displayName: "lesson.mov",
            duration: 0.5,
            mediaKind: .video
        )

        try viewModel.loadImportedAudio(media)

        XCTAssertTrue(viewModel.canShowVideoWindow)
        XCTAssertTrue(viewModel.canToggleVideoWindow)
        XCTAssertTrue(viewModel.isVideoWindowOpen)
        XCTAssertEqual(videoFollower.loadedVideoURL, videoURL)
        XCTAssertEqual(videoFollower.showWindowEvents.count, 1)
        XCTAssertFalse(viewModel.isProjectModified)

        let importEvent = try XCTUnwrap(videoFollower.showWindowEvents.last)
        XCTAssertEqual(importEvent.time, 0, accuracy: 0.0001)
        XCTAssertFalse(importEvent.isPlaying)
        XCTAssertEqual(importEvent.rate, AppSliderDefaults.playbackRate, accuracy: 0.0001)

        viewModel.setPlaybackRate(0.5)
        viewModel.play()

        viewModel.showVideoWindow()

        let event = try XCTUnwrap(videoFollower.showWindowEvents.last)
        XCTAssertEqual(event.time, viewModel.currentTime, accuracy: 0.0001)
        XCTAssertTrue(event.isPlaying)
        XCTAssertEqual(event.rate, 0.5, accuracy: 0.0001)

        viewModel.newProject()
    }

    @MainActor
    func testAudioImportDoesNotShowVideoWindow() throws {
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(videoFollower: videoFollower)
        let audioURL = try temporaryAudioFile(duration: 2)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let media = ImportedAudioFile(url: audioURL, displayName: "lesson.wav", duration: 0.5)

        try viewModel.loadImportedAudio(media)

        XCTAssertFalse(viewModel.canShowVideoWindow)
        XCTAssertFalse(viewModel.isVideoWindowOpen)
        XCTAssertTrue(videoFollower.showWindowEvents.isEmpty)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testToggleVideoWindowIsNoOpWithoutVideoMedia() {
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(videoFollower: videoFollower)

        XCTAssertFalse(viewModel.canToggleVideoWindow)

        viewModel.toggleVideoWindow()

        XCTAssertTrue(videoFollower.toggleWindowEvents.isEmpty)
    }

    @MainActor
    func testToggleVideoWindowForwardsCurrentPlaybackStateForVideoMedia() throws {
        let engine = MockPlaybackEngine()
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine, videoFollower: videoFollower)
        let audioURL = try temporaryAudioFile(duration: 2)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let videoURL = URL(fileURLWithPath: "/tmp/lesson.mov")
        let media = ImportedAudioFile(
            url: audioURL,
            sourceMediaURL: videoURL,
            displayName: "lesson.mov",
            duration: 0.5,
            mediaKind: .video
        )

        try viewModel.loadImportedAudio(media)
        videoFollower.closeWindow()
        viewModel.markProjectClean()
        viewModel.setPlaybackRate(0.5)
        viewModel.play()
        viewModel.toggleVideoWindow()

        let event = try XCTUnwrap(videoFollower.toggleWindowEvents.last)
        XCTAssertEqual(event.time, viewModel.currentTime, accuracy: 0.0001)
        XCTAssertTrue(event.isPlaying)
        XCTAssertEqual(event.rate, 0.5, accuracy: 0.0001)
        XCTAssertEqual(videoFollower.showWindowEvents.count, 1)
    }

    @MainActor
    func testVideoWindowOpenCloseUpdatesProjectModifiedState() throws {
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(videoFollower: videoFollower)
        let audioURL = try temporaryAudioFile(duration: 2)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let media = ImportedAudioFile(
            url: audioURL,
            sourceMediaURL: URL(fileURLWithPath: "/tmp/lesson.mov"),
            displayName: "lesson.mov",
            duration: 0.5,
            mediaKind: .video
        )

        try viewModel.loadImportedAudio(media)

        XCTAssertTrue(viewModel.isVideoWindowOpen)
        XCTAssertFalse(viewModel.isProjectModified)

        videoFollower.closeWindow()

        XCTAssertFalse(viewModel.isVideoWindowOpen)
        XCTAssertTrue(viewModel.isProjectModified)

        viewModel.showVideoWindow()

        XCTAssertTrue(viewModel.isVideoWindowOpen)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testNewProjectUnloadsPreparedVideoFollower() throws {
        let engine = MockPlaybackEngine()
        let videoFollower = MockVideoFollower()
        let viewModel = AudioPlayerViewModel(playbackEngine: engine, videoFollower: videoFollower)
        let audioURL = try temporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let media = ImportedAudioFile(
            url: audioURL,
            sourceMediaURL: URL(fileURLWithPath: "/tmp/lesson.mov"),
            displayName: "lesson.mov",
            duration: 0.5,
            mediaKind: .video
        )

        try viewModel.loadImportedAudio(media)
        viewModel.newProject()

        XCTAssertTrue(videoFollower.didUnload)
        XCTAssertFalse(viewModel.canShowVideoWindow)
        XCTAssertFalse(viewModel.isVideoWindowOpen)
    }
}
