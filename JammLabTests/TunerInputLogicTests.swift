import XCTest
@testable import JammLab

final class TunerInputLogicTests: XCTestCase {
    func testTunerInputServiceErrorNamesInvalidElementStatusForUsers() {
        XCTAssertEqual(
            TunerInputServiceError.inputDeviceSwitchFailed(-10877).localizedDescription,
            "Audio input device switch failed with status -10877 (kAudioUnitErr_InvalidElement)."
        )
    }

    func testTunerInputSignalLevelNormalizesRMSAsDBFS() {
        XCTAssertEqual(TunerInputSignalLevel.normalized(rms: 0), 0)
        XCTAssertEqual(TunerInputSignalLevel.normalized(rms: pow(10, -70.0 / 20.0)), 0)
        XCTAssertEqual(TunerInputSignalLevel.normalized(rms: pow(10, -60.0 / 20.0)), 0)
        XCTAssertEqual(TunerInputSignalLevel.normalized(rms: pow(10, -36.0 / 20.0)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(TunerInputSignalLevel.normalized(rms: pow(10, -12.0 / 20.0)), 1)
        XCTAssertEqual(TunerInputSignalLevel.normalized(rms: 1), 1)
    }
}
