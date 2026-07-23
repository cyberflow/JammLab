#import <XCTest/XCTest.h>

#include "../JammLab/Transcription/Native/BasicPitchTranscriptionEngine.h"

#include <cmath>
#include <filesystem>
#include <fstream>
#include <vector>

using jammlab::transcription::BasicPitchTranscriptionEngine;
using jammlab::transcription::Configuration;
using jammlab::transcription::Error;
using jammlab::transcription::ErrorCode;

@interface BasicPitchNativeTests : XCTestCase
@end

@implementation BasicPitchNativeTests

- (void)testRejectsEmptyInputBeforeLoadingModel
{
    BasicPitchTranscriptionEngine engine(std::filesystem::path("/missing"));
    try {
        engine.transcribePCMFile("/missing", 0, BasicPitchTranscriptionEngine::requiredSampleRate, Configuration {});
    } catch (const Error& error) {
        XCTAssertEqual(error.code(), ErrorCode::emptyInput);
    }
}

- (void)testRejectsUnsupportedSampleRate
{
    BasicPitchTranscriptionEngine engine(std::filesystem::path("/missing"));
    try {
        engine.transcribePCMFile("/missing", 1, 44100, Configuration {});
        XCTFail(@"Expected unsupported sample rate");
    } catch (const Error& error) {
        XCTAssertEqual(error.code(), ErrorCode::unsupportedSampleRate);
    }
}

- (void)testCancellationPreventsModelLoad
{
    BasicPitchTranscriptionEngine engine(std::filesystem::path("/missing"));
    try {
        engine.transcribePCMFile(
            "/missing",
            1,
            BasicPitchTranscriptionEngine::requiredSampleRate,
            Configuration {},
            [](double) { return false; }
        );
        XCTFail(@"Expected cancellation");
    } catch (const Error& error) {
        XCTAssertEqual(error.code(), ErrorCode::cancelled);
    }
}

- (void)testBundledModelTranscribesGeneratedPolyphonicChord
{
    NSURL *featureModel = [[NSBundle mainBundle] URLForResource:@"features_model"
                                                  withExtension:@"ort"
                                                   subdirectory:@"BasicPitchModel"];
    XCTAssertNotNil(featureModel);
    if (featureModel == nil) {
        return;
    }

    const auto sampleRate = BasicPitchTranscriptionEngine::requiredSampleRate;
    const auto sampleCount = static_cast<std::size_t>(sampleRate * 3.0);
    std::vector<float> samples(sampleCount, 0.0f);
    for (std::size_t index = 0; index < sampleCount; ++index) {
        const auto time = static_cast<double>(index) / sampleRate;
        const auto envelope = std::min(1.0, std::min(time * 20.0, (3.0 - time) * 20.0));
        samples[index] = static_cast<float>(
            envelope * 0.35 * (std::sin(2.0 * M_PI * 440.0 * time)
                + std::sin(2.0 * M_PI * 523.2511306 * time))
        );
    }

    const auto temporaryURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"basic-pitch-golden-%@.f32", NSUUID.UUID.UUIDString]]];
    {
        std::ofstream output(temporaryURL.fileSystemRepresentation, std::ios::binary);
        output.write(
            reinterpret_cast<const char *>(samples.data()),
            static_cast<std::streamsize>(samples.size() * sizeof(float))
        );
    }

    const auto modelDirectory = std::filesystem::path(
        featureModel.URLByDeletingLastPathComponent.fileSystemRepresentation
    );
    BasicPitchTranscriptionEngine engine(modelDirectory);
    std::vector<double> progress;
    const auto result = engine.transcribePCMFile(
        temporaryURL.fileSystemRepresentation,
        sampleCount,
        sampleRate,
        Configuration {},
        [&](double value) {
            progress.push_back(value);
            return true;
        }
    );
    [[NSFileManager defaultManager] removeItemAtURL:temporaryURL error:nil];

    const auto containsPitch = [&](int pitch) {
        return std::any_of(result.notes.begin(), result.notes.end(), [&](const auto& note) {
            return note.pitch == pitch
                && note.startTimeSeconds < 0.5
                && note.endTimeSeconds > 2.0;
        });
    };
    XCTAssertTrue(containsPitch(69));
    XCTAssertTrue(containsPitch(72));
    XCTAssertFalse(progress.empty());
    XCTAssertEqualWithAccuracy(progress.back(), 1.0, 0.000001);
    XCTAssertGreaterThan(result.timings.inferenceSeconds, 0);
}

@end
