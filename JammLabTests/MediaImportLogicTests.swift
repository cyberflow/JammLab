import XCTest
@testable import JammLab

final class MediaImportLogicTests: XCTestCase {
    func testMediaImporterClassifiesSupportedFormats() {
        let importer = AudioFileImporter()

        XCTAssertEqual(importer.mediaKind(for: URL(fileURLWithPath: "/tmp/song.mp3")), .audio)
        XCTAssertEqual(importer.mediaKind(for: URL(fileURLWithPath: "/tmp/song.wav")), .audio)
        XCTAssertEqual(importer.mediaKind(for: URL(fileURLWithPath: "/tmp/lesson.mp4")), .video)
        XCTAssertEqual(importer.mediaKind(for: URL(fileURLWithPath: "/tmp/lesson.mov")), .video)
        XCTAssertEqual(importer.mediaKind(for: URL(fileURLWithPath: "/tmp/lesson.m4v")), .video)
        XCTAssertNil(importer.mediaKind(for: URL(fileURLWithPath: "/tmp/document.pdf")))
    }

    func testMediaCacheKeyIsStableForSameFileIdentity() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try temporaryFile(in: directory, name: "lesson.mp4", contents: "video")
        let modificationDate = Date(timeIntervalSince1970: 1234)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: url.path)

        let firstKey = VideoAudioExtractionService.cacheKey(for: url)
        let secondKey = VideoAudioExtractionService.cacheKey(for: url)

        XCTAssertEqual(firstKey, secondKey)

        let changedURL = try temporaryFile(in: directory, name: "changed-lesson.mp4", contents: "changed-video")
        try FileManager.default.setAttributes(
            [.modificationDate: modificationDate.addingTimeInterval(10)],
            ofItemAtPath: changedURL.path
        )

        XCTAssertNotEqual(VideoAudioExtractionService.cacheKey(for: changedURL), firstKey)
    }
}
