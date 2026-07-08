import XCTest
@testable import JammLab

final class TunerInputDeviceResolverTests: XCTestCase {
    func testTunerInputDeviceResolverUsesSavedInputDevice() throws {
        let provider = MockAudioDeviceProvider()
        provider.inputDevicesResult = [
            AudioDeviceInfo(uid: "input-1", name: "Interface Input", kind: .input, isDefault: false)
        ]
        provider.deviceIDs["input-1"] = 42
        provider.defaultInputDeviceID = 7

        let selection = try TunerInputDeviceResolver(audioDeviceProvider: provider)
            .resolveInputDevice(selectedUID: "input-1")

        XCTAssertEqual(selection.id, 42)
        XCTAssertEqual(selection.name, "Interface Input")
        XCTAssertEqual(provider.defaultDeviceCallKinds, [])
    }

    func testTunerInputDeviceResolverUsesDefaultWhenInputSelectionIsNil() throws {
        let provider = MockAudioDeviceProvider()
        provider.defaultInputDeviceID = 7
        provider.inputDevicesResult = [
            AudioDeviceInfo(uid: "default-input", name: "Default Input", kind: .input, isDefault: true)
        ]

        let selection = try TunerInputDeviceResolver(audioDeviceProvider: provider)
            .resolveInputDevice(selectedUID: nil)

        XCTAssertEqual(selection.id, 7)
        XCTAssertEqual(selection.name, "Default Input")
    }

    func testTunerInputDeviceResolverDoesNotFallbackWhenSavedInputDeviceIsMissing() {
        let provider = MockAudioDeviceProvider()
        provider.defaultInputDeviceID = 7

        XCTAssertThrowsError(
            try TunerInputDeviceResolver(audioDeviceProvider: provider)
                .resolveInputDevice(selectedUID: "missing-input")
        )
        XCTAssertEqual(provider.defaultDeviceCallKinds, [])
    }
}
