import XCTest
@testable import JammLab

final class ControlLogicTests: XCTestCase {
    func testAbletonNumberFieldLogicClampsAndResetsDefault() {
        let config = AbletonNumberFieldConfiguration(
            minValue: 40,
            maxValue: 240,
            defaultValue: 300,
            step: 1,
            precision: 0
        )

        XCTAssertEqual(AbletonNumberFieldLogic.clamp(20, configuration: config), 40, accuracy: 0.0001)
        XCTAssertEqual(AbletonNumberFieldLogic.clamp(300, configuration: config), 240, accuracy: 0.0001)
        XCTAssertEqual(AbletonNumberFieldLogic.resetValue(configuration: config), 240, accuracy: 0.0001)
    }

    func testAbletonNumberFieldLogicSnapsToIntegerAndFractionalSteps() {
        let integerConfig = AbletonNumberFieldConfiguration(
            minValue: 40,
            maxValue: 240,
            defaultValue: 120,
            step: 1,
            precision: 0
        )
        let fractionalConfig = AbletonNumberFieldConfiguration(
            minValue: -1,
            maxValue: 1,
            defaultValue: 0,
            step: 0.25,
            precision: 2
        )

        XCTAssertEqual(AbletonNumberFieldLogic.snapToStep(120.4, configuration: integerConfig), 120, accuracy: 0.0001)
        XCTAssertEqual(AbletonNumberFieldLogic.snapToStep(120.6, configuration: integerConfig), 121, accuracy: 0.0001)
        XCTAssertEqual(AbletonNumberFieldLogic.snapToStep(0.38, configuration: fractionalConfig), 0.5, accuracy: 0.0001)
    }

    func testAbletonNumberFieldLogicFormatsPrecision() {
        let integerConfig = AbletonNumberFieldConfiguration(
            minValue: 0,
            maxValue: 200,
            defaultValue: 120,
            step: 1,
            precision: 0
        )
        let decimalConfig = AbletonNumberFieldConfiguration(
            minValue: 0,
            maxValue: 2,
            defaultValue: 1,
            step: 0.01,
            precision: 2
        )
        let tempoConfig = AbletonNumberFieldConfiguration(
            minValue: 40,
            maxValue: 240,
            defaultValue: 120,
            step: 0.01,
            precision: 2
        )

        XCTAssertEqual(AbletonNumberFieldLogic.format(119.6, configuration: integerConfig), "120")
        XCTAssertEqual(AbletonNumberFieldLogic.format(1.235, configuration: decimalConfig), "1.24")
        XCTAssertEqual(AbletonNumberFieldLogic.format(120, configuration: tempoConfig), "120.00")
        XCTAssertEqual(AbletonNumberFieldLogic.format(240, configuration: tempoConfig), "240.00")
    }

    func testAbletonNumberFieldLogicParsesDecimalSeparatorsAndNegativeRules() {
        let positiveConfig = AbletonNumberFieldConfiguration(
            minValue: 0,
            maxValue: 200,
            defaultValue: 120,
            step: 0.1,
            precision: 1
        )
        let negativeConfig = AbletonNumberFieldConfiguration(
            minValue: -12,
            maxValue: 12,
            defaultValue: 0,
            step: 0.5,
            precision: 1
        )
        let hundredthsConfig = AbletonNumberFieldConfiguration(
            minValue: 40,
            maxValue: 240,
            defaultValue: 120,
            step: 0.01,
            precision: 2
        )

        XCTAssertEqual(try XCTUnwrap(AbletonNumberFieldLogic.parse("123,4", configuration: positiveConfig)), 123.4, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(AbletonNumberFieldLogic.parse("123.45", configuration: positiveConfig)), 123.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(AbletonNumberFieldLogic.parse("123.45", configuration: hundredthsConfig)), 123.45, accuracy: 0.0001)
        XCTAssertNil(AbletonNumberFieldLogic.parse("-1", configuration: positiveConfig))
        XCTAssertEqual(try XCTUnwrap(AbletonNumberFieldLogic.parse("-1.2", configuration: negativeConfig)), -1, accuracy: 0.0001)
        XCTAssertNil(AbletonNumberFieldLogic.parse("abc", configuration: negativeConfig))
    }

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

    func testAppKitDragThresholdUsesVerticalDistanceForNumberField() {
        XCTAssertFalse(AppKitDragThreshold.exceedsVerticalThreshold(deltaY: 2.9, threshold: 3))
        XCTAssertTrue(AppKitDragThreshold.exceedsVerticalThreshold(deltaY: 3, threshold: 3))
        XCTAssertTrue(AppKitDragThreshold.exceedsVerticalThreshold(deltaY: -3.1, threshold: 3))
    }

    func testAppKitDragThresholdUsesDominantAxisForValueSlider() {
        XCTAssertFalse(AppKitDragThreshold.exceedsDominantAxisThreshold(deltaX: 2.9, deltaY: 1, threshold: 3))
        XCTAssertTrue(AppKitDragThreshold.exceedsDominantAxisThreshold(deltaX: 3, deltaY: 1, threshold: 3))
        XCTAssertTrue(AppKitDragThreshold.exceedsDominantAxisThreshold(deltaX: 1, deltaY: -3.1, threshold: 3))
        XCTAssertTrue(AppKitDragThreshold.exceedsDominantAxisThreshold(deltaX: -2, deltaY: 4, threshold: 3))
    }
}
