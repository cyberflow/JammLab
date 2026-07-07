import AVFoundation
import XCTest
@testable import JammLab

final class AudioFileImporterDurationTests: XCTestCase {
    func testDecodedAudioDurationUsesPCMFrameLength() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jammlab-duration-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22_050)!
        buffer.frameLength = 22_050
        try file.write(from: buffer)

        let duration = try AudioFileImporter.decodedDuration(for: url)

        XCTAssertEqual(duration, 0.5, accuracy: 0.0001)
    }
}
