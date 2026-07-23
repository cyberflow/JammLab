#import "JMBasicPitchBridge.h"

#include "BasicPitchTranscriptionEngine.h"

#include <atomic>
#include <filesystem>
#include <memory>
#include <mutex>

NSErrorDomain const JMTranscriptionErrorDomain = @"com.jammlab.transcription";

@implementation JMTranscriptionConfiguration

- (instancetype)init
{
    self = [super init];
    if (self) {
        _noteSensitivity = 0.7f;
        _splitSensitivity = 0.5f;
        _minimumNoteDurationMilliseconds = 125.0f;
        _includePitchBends = NO;
        _windowDurationSeconds = 30.0;
        _overlapDurationSeconds = 2.0;
    }
    return self;
}

@end

@interface JMTranscriptionNote ()
- (instancetype)initWithPitch:(NSInteger)pitch
             startTimeSeconds:(double)startTimeSeconds
               endTimeSeconds:(double)endTimeSeconds
                   confidence:(double)confidence
                   pitchBends:(NSArray<NSNumber *> *)pitchBends;
@end

@implementation JMTranscriptionNote

- (instancetype)initWithPitch:(NSInteger)pitch
             startTimeSeconds:(double)startTimeSeconds
               endTimeSeconds:(double)endTimeSeconds
                   confidence:(double)confidence
                   pitchBends:(NSArray<NSNumber *> *)pitchBends
{
    self = [super init];
    if (self) {
        _pitch = pitch;
        _startTimeSeconds = startTimeSeconds;
        _endTimeSeconds = endTimeSeconds;
        _confidence = confidence;
        _pitchBends = [pitchBends copy];
    }
    return self;
}

@end

@interface JMTranscriptionTimings ()
- (instancetype)initWithModelLoadSeconds:(double)modelLoadSeconds
                        inferenceSeconds:(double)inferenceSeconds
                    postProcessingSeconds:(double)postProcessingSeconds
                            totalSeconds:(double)totalSeconds;
@end

@implementation JMTranscriptionTimings

- (instancetype)initWithModelLoadSeconds:(double)modelLoadSeconds
                        inferenceSeconds:(double)inferenceSeconds
                    postProcessingSeconds:(double)postProcessingSeconds
                            totalSeconds:(double)totalSeconds
{
    self = [super init];
    if (self) {
        _modelLoadSeconds = modelLoadSeconds;
        _inferenceSeconds = inferenceSeconds;
        _postProcessingSeconds = postProcessingSeconds;
        _totalSeconds = totalSeconds;
    }
    return self;
}

@end

@interface JMTranscriptionResult ()
- (instancetype)initWithNotes:(NSArray<JMTranscriptionNote *> *)notes
      processedDurationSeconds:(double)processedDurationSeconds
                      warnings:(NSArray<NSString *> *)warnings
                       timings:(JMTranscriptionTimings *)timings;
@end

@implementation JMTranscriptionResult

- (instancetype)initWithNotes:(NSArray<JMTranscriptionNote *> *)notes
      processedDurationSeconds:(double)processedDurationSeconds
                      warnings:(NSArray<NSString *> *)warnings
                       timings:(JMTranscriptionTimings *)timings
{
    self = [super init];
    if (self) {
        _notes = [notes copy];
        _processedDurationSeconds = processedDurationSeconds;
        _warnings = [warnings copy];
        _timings = timings;
    }
    return self;
}

@end

@interface JMTranscriptionCancellationToken () {
@public
    std::atomic_bool _cancelled;
}
@end

@implementation JMTranscriptionCancellationToken

- (instancetype)init
{
    self = [super init];
    if (self) {
        _cancelled.store(false);
    }
    return self;
}

- (void)cancel
{
    _cancelled.store(true);
}

@end

namespace
{
JMTranscriptionErrorCode errorCode(jammlab::transcription::ErrorCode code)
{
    using NativeCode = jammlab::transcription::ErrorCode;
    switch (code) {
        case NativeCode::emptyInput:
            return JMTranscriptionErrorCodeEmptyInput;
        case NativeCode::unsupportedSampleRate:
            return JMTranscriptionErrorCodeUnsupportedSampleRate;
        case NativeCode::audioReadFailed:
            return JMTranscriptionErrorCodeAudioReadFailed;
        case NativeCode::modelResourceMissing:
            return JMTranscriptionErrorCodeModelResourceMissing;
        case NativeCode::modelInitializationFailed:
            return JMTranscriptionErrorCodeModelInitializationFailed;
        case NativeCode::inferenceFailed:
            return JMTranscriptionErrorCodeInferenceFailed;
        case NativeCode::invalidModelOutput:
            return JMTranscriptionErrorCodeInvalidModelOutput;
        case NativeCode::cancelled:
            return JMTranscriptionErrorCodeCancelled;
    }
}

NSArray<NSNumber *> *pitchBends(const std::vector<int>& nativeBends)
{
    NSMutableArray<NSNumber *> *values = [NSMutableArray arrayWithCapacity:nativeBends.size()];
    for (const auto bend: nativeBends) {
        [values addObject:@(bend)];
    }
    return values;
}
} // namespace

@interface JMBasicPitchBridge () {
    std::unique_ptr<jammlab::transcription::BasicPitchTranscriptionEngine> _engine;
    std::mutex _engineMutex;
}
@end

@implementation JMBasicPitchBridge

- (nullable JMTranscriptionResult *)transcribePCMFileAtURL:(NSURL *)fileURL
                                               sampleCount:(NSUInteger)sampleCount
                                                sampleRate:(double)sampleRate
                                             configuration:(JMTranscriptionConfiguration *)configuration
                                         cancellationToken:(JMTranscriptionCancellationToken *)cancellationToken
                                                  progress:(void (^ _Nullable)(double progress))progress
                                                     error:(NSError **)error
{
    std::lock_guard<std::mutex> lock(_engineMutex);

    @autoreleasepool {
        NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"features_model"
                                                  withExtension:@"ort"
                                                   subdirectory:@"BasicPitchModel"];
        if (modelURL == nil) {
            if (error != nullptr) {
                *error = [NSError errorWithDomain:JMTranscriptionErrorDomain
                                             code:JMTranscriptionErrorCodeModelResourceMissing
                                         userInfo:@{NSLocalizedDescriptionKey: @"The built-in Basic Pitch model is missing."}];
            }
            return nil;
        }

        try {
            if (!_engine) {
                const auto modelDirectory = std::filesystem::path(
                    modelURL.URLByDeletingLastPathComponent.fileSystemRepresentation
                );
                _engine = std::make_unique<jammlab::transcription::BasicPitchTranscriptionEngine>(modelDirectory);
            }

            jammlab::transcription::Configuration nativeConfiguration;
            nativeConfiguration.noteSensitivity = configuration.noteSensitivity;
            nativeConfiguration.splitSensitivity = configuration.splitSensitivity;
            nativeConfiguration.minimumNoteDurationMilliseconds =
                configuration.minimumNoteDurationMilliseconds;
            nativeConfiguration.includePitchBends = configuration.includePitchBends;
            nativeConfiguration.windowDurationSeconds = configuration.windowDurationSeconds;
            nativeConfiguration.overlapDurationSeconds = configuration.overlapDurationSeconds;

            const auto nativeResult = _engine->transcribePCMFile(
                std::filesystem::path(fileURL.fileSystemRepresentation),
                sampleCount,
                sampleRate,
                nativeConfiguration,
                [&](double value) {
                    if (cancellationToken->_cancelled.load()) {
                        return false;
                    }
                    if (progress) {
                        progress(value);
                    }
                    return !cancellationToken->_cancelled.load();
                }
            );

            NSMutableArray<JMTranscriptionNote *> *notes =
                [NSMutableArray arrayWithCapacity:nativeResult.notes.size()];
            for (const auto& note: nativeResult.notes) {
                [notes addObject:[[JMTranscriptionNote alloc]
                    initWithPitch:note.pitch
                    startTimeSeconds:note.startTimeSeconds
                    endTimeSeconds:note.endTimeSeconds
                    confidence:note.confidence
                    pitchBends:pitchBends(note.pitchBends)]];
            }

            NSMutableArray<NSString *> *warnings =
                [NSMutableArray arrayWithCapacity:nativeResult.warnings.size()];
            for (const auto& warning: nativeResult.warnings) {
                [warnings addObject:[NSString stringWithUTF8String:warning.c_str()]];
            }

            const auto& timings = nativeResult.timings;
            JMTranscriptionTimings *objectiveTimings = [[JMTranscriptionTimings alloc]
                initWithModelLoadSeconds:timings.modelLoadSeconds
                inferenceSeconds:timings.inferenceSeconds
                postProcessingSeconds:timings.postProcessingSeconds
                totalSeconds:timings.totalSeconds];
            return [[JMTranscriptionResult alloc]
                initWithNotes:notes
                processedDurationSeconds:nativeResult.processedDurationSeconds
                warnings:warnings
                timings:objectiveTimings];
        } catch (const jammlab::transcription::Error& exception) {
            if (error != nullptr) {
                *error = [NSError errorWithDomain:JMTranscriptionErrorDomain
                                             code:errorCode(exception.code())
                                         userInfo:@{
                                             NSLocalizedDescriptionKey:
                                                 [NSString stringWithUTF8String:exception.what()]
                                         }];
            }
        } catch (const std::exception& exception) {
            if (error != nullptr) {
                *error = [NSError errorWithDomain:JMTranscriptionErrorDomain
                                             code:JMTranscriptionErrorCodeInferenceFailed
                                         userInfo:@{
                                             NSLocalizedDescriptionKey:
                                                 [NSString stringWithUTF8String:exception.what()]
                                         }];
            }
        }
    }
    return nil;
}

@end
