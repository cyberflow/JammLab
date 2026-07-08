import XCTest
@testable import JammLab

final class JammValueSliderLogicTests: XCTestCase {
    func testJammValueSliderLogicClampsAndResetsDefault() {
        let config = JammValueSliderConfiguration(
            minValue: 0,
            maxValue: 1,
            defaultValue: 1.5,
            step: 0.01,
            precision: 2
        )

        XCTAssertEqual(JammValueSliderLogic.clamp(-1, configuration: config), 0, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.clamp(2, configuration: config), 1, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.resetValue(configuration: config), 1, accuracy: 0.0001)
    }

    func testJammValueSliderLogicNormalizesRanges() {
        let volumeConfig = JammValueSliderConfiguration(
            minValue: 0,
            maxValue: 1,
            defaultValue: 0.75,
            step: 0.01,
            precision: 2
        )
        let gainConfig = JammValueSliderConfiguration(
            minValue: -60,
            maxValue: 12,
            defaultValue: 0,
            step: 0.1,
            precision: 1
        )
        let reversedConfig = JammValueSliderConfiguration(
            minValue: 12,
            maxValue: -60,
            defaultValue: 0,
            step: 0.1,
            precision: 1
        )

        XCTAssertEqual(JammValueSliderLogic.normalizedValue(0.25, configuration: volumeConfig), 0.25, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.normalizedValue(-60, configuration: gainConfig), 0, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.normalizedValue(12, configuration: gainConfig), 1, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.normalizedValue(-24, configuration: gainConfig), 0.5, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.normalizedValue(-24, configuration: reversedConfig), 0.5, accuracy: 0.0001)
    }

    func testJammValueSliderLogicSnapsAndFormats() {
        let integerConfig = JammValueSliderConfiguration(
            minValue: 0,
            maxValue: 10,
            defaultValue: 5,
            step: 1,
            precision: 0
        )
        let fractionalConfig = JammValueSliderConfiguration(
            minValue: -1,
            maxValue: 1,
            defaultValue: 0,
            step: 0.25,
            precision: 2
        )

        XCTAssertEqual(JammValueSliderLogic.snapToStep(4.4, configuration: integerConfig), 4, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.snapToStep(4.6, configuration: integerConfig), 5, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.snapToStep(0.38, configuration: fractionalConfig), 0.5, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.format(0.38, configuration: fractionalConfig), "0.50")
    }

    func testJammValueSliderLogicUsesDominantDragAxis() {
        let config = JammValueSliderConfiguration(
            minValue: 0,
            maxValue: 1,
            defaultValue: 0.5,
            step: 0.01,
            sensitivity: 1,
            precision: 2
        )

        XCTAssertEqual(JammValueSliderLogic.dragValue(startValue: 0.5, deltaX: 10, deltaY: 2, configuration: config), 0.6, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.dragValue(startValue: 0.5, deltaX: 2, deltaY: 10, configuration: config), 0.6, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.dragValue(startValue: 0.5, deltaX: -10, deltaY: 2, configuration: config), 0.4, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.dragValue(startValue: 0.5, deltaX: 2, deltaY: -10, configuration: config), 0.4, accuracy: 0.0001)
    }

    func testJammValueSliderLogicSupportsSlowerIntegerPitchDrag() {
        let config = JammValueSliderConfiguration(
            minValue: -12,
            maxValue: 12,
            defaultValue: 0,
            step: 1,
            sensitivity: 0.08,
            precision: 0
        )

        XCTAssertEqual(JammValueSliderLogic.dragValue(startValue: 0, deltaX: 6, deltaY: 0, configuration: config), 0, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.dragValue(startValue: 0, deltaX: 7, deltaY: 0, configuration: config), 1, accuracy: 0.0001)
        XCTAssertEqual(JammValueSliderLogic.dragValue(startValue: 0, deltaX: -7, deltaY: 0, configuration: config), -1, accuracy: 0.0001)
    }
}
