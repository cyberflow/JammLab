#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const JMTranscriptionErrorDomain;

typedef NS_ERROR_ENUM(JMTranscriptionErrorDomain, JMTranscriptionErrorCode) {
    JMTranscriptionErrorCodeEmptyInput = 1,
    JMTranscriptionErrorCodeUnsupportedSampleRate,
    JMTranscriptionErrorCodeAudioReadFailed,
    JMTranscriptionErrorCodeModelResourceMissing,
    JMTranscriptionErrorCodeModelInitializationFailed,
    JMTranscriptionErrorCodeInferenceFailed,
    JMTranscriptionErrorCodeInvalidModelOutput,
    JMTranscriptionErrorCodeCancelled
};

@interface JMTranscriptionConfiguration : NSObject
@property(nonatomic) float noteSensitivity;
@property(nonatomic) float splitSensitivity;
@property(nonatomic) float minimumNoteDurationMilliseconds;
@property(nonatomic) BOOL includePitchBends;
@property(nonatomic) double windowDurationSeconds;
@property(nonatomic) double overlapDurationSeconds;
@end

@interface JMTranscriptionNote : NSObject
@property(nonatomic, readonly) NSInteger pitch;
@property(nonatomic, readonly) double startTimeSeconds;
@property(nonatomic, readonly) double endTimeSeconds;
@property(nonatomic, readonly) double confidence;
@property(nonatomic, copy, readonly) NSArray<NSNumber *> *pitchBends;
@end

@interface JMTranscriptionTimings : NSObject
@property(nonatomic, readonly) double modelLoadSeconds;
@property(nonatomic, readonly) double inferenceSeconds;
@property(nonatomic, readonly) double postProcessingSeconds;
@property(nonatomic, readonly) double totalSeconds;
@end

@interface JMTranscriptionResult : NSObject
@property(nonatomic, copy, readonly) NSArray<JMTranscriptionNote *> *notes;
@property(nonatomic, readonly) double processedDurationSeconds;
@property(nonatomic, copy, readonly) NSArray<NSString *> *warnings;
@property(nonatomic, strong, readonly) JMTranscriptionTimings *timings;
@end

@interface JMTranscriptionCancellationToken : NSObject
- (void)cancel;
@end

@interface JMBasicPitchBridge : NSObject
- (nullable JMTranscriptionResult *)transcribePCMFileAtURL:(NSURL *)fileURL
                                               sampleCount:(NSUInteger)sampleCount
                                                sampleRate:(double)sampleRate
                                             configuration:(JMTranscriptionConfiguration *)configuration
                                         cancellationToken:(JMTranscriptionCancellationToken *)cancellationToken
                                                  progress:(void (^ _Nullable)(double progress))progress
                                                     error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
