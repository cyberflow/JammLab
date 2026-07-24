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
        XCTFail(@"Expected empty input");
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

- (void)testStitchingOnlyMergesMatchingNotesAtWindowBoundary
{
    using jammlab::transcription::Note;
    std::vector<Note> notes {
        {60, 1.0, 1.45, 0.7, {}},
        {60, 1.48, 1.8, 0.8, {}},
        {64, 1.7, 2.0, 0.9, {}},
        {64, 2.0, 2.4, 0.85, {}},
        {67, 2.0, 2.5, 0.75, {}}
    };

    jammlab::transcription::detail::stitchNotesAtWindowBoundaries(notes, {2.0});

    XCTAssertEqual(notes.size(), 4u);
    const auto countPitch = [&](int pitch) {
        return std::count_if(notes.begin(), notes.end(), [&](const Note& note) {
            return note.pitch == pitch;
        });
    };
    XCTAssertEqual(countPitch(60), 2);
    XCTAssertEqual(countPitch(64), 1);
    XCTAssertEqual(countPitch(67), 1);
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
    XCTAssertTrue(std::is_sorted(progress.begin(), progress.end()));
    XCTAssertGreaterThan(result.timings.inferenceSeconds, 0);

    try {
        engine.transcribePCMFile(
            temporaryURL.fileSystemRepresentation,
            sampleCount + 100,
            sampleRate,
            Configuration {}
        );
        XCTFail(@"Expected truncated PCM error");
    } catch (const Error& error) {
        XCTAssertEqual(error.code(), ErrorCode::audioReadFailed);
    }

    try {
        engine.transcribePCMFile(
            temporaryURL.fileSystemRepresentation,
            sampleCount,
            sampleRate,
            Configuration {},
            [](double value) { return value < 0.05; }
        );
        XCTFail(@"Expected in-flight cancellation");
    } catch (const Error& error) {
        XCTAssertEqual(error.code(), ErrorCode::cancelled);
    }

    [[NSFileManager defaultManager] removeItemAtURL:temporaryURL error:nil];
}

@end
