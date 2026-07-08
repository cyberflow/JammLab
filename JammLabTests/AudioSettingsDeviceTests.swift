import XCTest
@testable import JammLab

final class AudioSettingsDeviceTests: XCTestCase {
    func testAudioSettingsDeviceLoaderDoesNotReadInputDevicesBeforePermission() async {
        let provider = MockAudioDeviceProvider()
        provider.inputDevicesResult = [
            AudioDeviceInfo(uid: "input-1", name: "Input 1", kind: .input, isDefault: true)
        ]
        provider.outputDevicesResult = [
            AudioDeviceInfo(uid: "output-1", name: "Output 1", kind: .output, isDefault: true)
        ]
        let permission = MockAudioInputPermissionProvider(status: .notDetermined)
        let loader = AudioSettingsDeviceLoader(deviceProvider: provider, inputPermissionProvider: permission)

        let result = await loader.refreshDevices()

        XCTAssertEqual(provider.inputDevicesCallCount, 0)
        XCTAssertEqual(provider.outputDevicesCallCount, 1)
        XCTAssertEqual(result.inputDevices, [])
        XCTAssertEqual(result.outputDevices.map(\.uid), ["output-1"])
        XCTAssertEqual(result.inputPermissionStatus, .notDetermined)
        XCTAssertEqual(permission.requestAccessCount, 0)
    }

    func testAudioSettingsDeviceLoaderReadsInputDevicesAfterPermission() async {
        let provider = MockAudioDeviceProvider()
        provider.inputDevicesResult = [
            AudioDeviceInfo(uid: "input-1", name: "Input 1", kind: .input, isDefault: true)
        ]
        provider.outputDevicesResult = [
            AudioDeviceInfo(uid: "output-1", name: "Output 1", kind: .output, isDefault: true)
        ]
        let permission = MockAudioInputPermissionProvider(status: .authorized)
        let loader = AudioSettingsDeviceLoader(deviceProvider: provider, inputPermissionProvider: permission)

        let result = await loader.refreshDevices()

        XCTAssertEqual(provider.inputDevicesCallCount, 1)
        XCTAssertEqual(provider.outputDevicesCallCount, 1)
        XCTAssertEqual(result.inputDevices.map(\.uid), ["input-1"])
        XCTAssertEqual(result.outputDevices.map(\.uid), ["output-1"])
        XCTAssertEqual(permission.requestAccessCount, 0)
    }

    func testAudioSettingsDevicePickerShowsSystemDefaultForUnavailableSavedUID() {
        let devices = [
            AudioDeviceInfo(uid: "input-1", name: "Input 1", kind: .input, isDefault: true)
        ]

        XCTAssertNil(AudioSettingsDevicePickerSelection.visibleUID(
            selectedUID: "missing-input",
            devices: devices
        ))
    }

    func testAudioSettingsDevicePickerUsesSavedUIDWhenAvailable() {
        let devices = [
            AudioDeviceInfo(uid: "input-1", name: "Input 1", kind: .input, isDefault: true)
        ]

        XCTAssertEqual(
            AudioSettingsDevicePickerSelection.visibleUID(selectedUID: "input-1", devices: devices),
            "input-1"
        )
    }
}
