#include "BasicPitchTranscriptionEngine.h"

#include "Engine/BasicPitch.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <fstream>
#include <limits>
#include <utility>

namespace jammlab::transcription
{
namespace
{
using Clock = std::chrono::steady_clock;

constexpr std::size_t minimumModelSamples = 2 * static_cast<std::size_t>(BASIC_PITCH_SAMPLE_RATE);
constexpr double progressReservedForPostProcessing = 0.02;
constexpr double boundaryToleranceSeconds = 0.08;

double elapsedSeconds(Clock::time_point start)
{
    return std::chrono::duration<double>(Clock::now() - start).count();
}

void checkCancellation(const ProgressCallback& callback, double progress)
{
    if (callback && !callback(std::clamp(progress, 0.0, 1.0))) {
        throw Error(ErrorCode::cancelled, "Transcription was cancelled");
    }
}

void validateConfiguration(const Configuration& configuration)
{
    if (!std::isfinite(configuration.windowDurationSeconds)
        || configuration.windowDurationSeconds < 2.0
        || !std::isfinite(configuration.overlapDurationSeconds)
        || configuration.overlapDurationSeconds < 0
        || configuration.overlapDurationSeconds >= configuration.windowDurationSeconds) {
        throw Error(ErrorCode::inferenceFailed, "Invalid transcription window configuration");
    }
}

void sanitizeSamples(std::vector<float>& samples)
{
    for (auto& sample: samples) {
        sample = std::isfinite(sample) ? std::clamp(sample, -1.0f, 1.0f) : 0.0f;
    }
}

void stitchNotes(std::vector<Note>& notes)
{
    std::sort(notes.begin(), notes.end(), [](const Note& lhs, const Note& rhs) {
        if (lhs.startTimeSeconds != rhs.startTimeSeconds) {
            return lhs.startTimeSeconds < rhs.startTimeSeconds;
        }
        if (lhs.pitch != rhs.pitch) {
            return lhs.pitch < rhs.pitch;
        }
        return lhs.endTimeSeconds < rhs.endTimeSeconds;
    });

    std::vector<Note> stitched;
    stitched.reserve(notes.size());
    for (auto& note: notes) {
        if (note.pitch < MIN_MIDI_NOTE || note.pitch > MAX_MIDI_NOTE
            || !std::isfinite(note.startTimeSeconds)
            || !std::isfinite(note.endTimeSeconds)
            || note.endTimeSeconds <= note.startTimeSeconds
            || !std::isfinite(note.confidence)) {
            continue;
        }

        auto duplicate = std::find_if(stitched.rbegin(), stitched.rend(), [&](const Note& candidate) {
            if (candidate.startTimeSeconds + boundaryToleranceSeconds < note.startTimeSeconds
                && candidate.endTimeSeconds + boundaryToleranceSeconds < note.startTimeSeconds) {
                return false;
            }
            return candidate.pitch == note.pitch
                && candidate.endTimeSeconds + boundaryToleranceSeconds >= note.startTimeSeconds;
        });

        if (duplicate != stitched.rend()) {
            duplicate->startTimeSeconds = std::min(duplicate->startTimeSeconds, note.startTimeSeconds);
            duplicate->endTimeSeconds = std::max(duplicate->endTimeSeconds, note.endTimeSeconds);
            duplicate->confidence = std::max(duplicate->confidence, note.confidence);
            if (duplicate->pitchBends.empty()) {
                duplicate->pitchBends = std::move(note.pitchBends);
            }
        } else {
            stitched.push_back(std::move(note));
        }
    }
    notes = std::move(stitched);
}

} // namespace

Error::Error(ErrorCode code, const std::string& message)
    : std::runtime_error(message)
    , code_(code)
{
}

ErrorCode Error::code() const noexcept
{
    return code_;
}

BasicPitchTranscriptionEngine::BasicPitchTranscriptionEngine(std::filesystem::path modelDirectory)
    : modelDirectory_(std::move(modelDirectory))
{
}

BasicPitchTranscriptionEngine::~BasicPitchTranscriptionEngine() = default;

void BasicPitchTranscriptionEngine::ensureModelLoaded(Timings& timings)
{
    if (model_) {
        return;
    }

    const auto start = Clock::now();
    if (!std::filesystem::is_directory(modelDirectory_)) {
        throw Error(ErrorCode::modelResourceMissing, "Basic Pitch model directory is missing");
    }

    try {
        model_ = std::make_unique<BasicPitch>(modelDirectory_);
    } catch (const std::exception& exception) {
        throw Error(ErrorCode::modelInitializationFailed, exception.what());
    }
    timings.modelLoadSeconds = elapsedSeconds(start);
}

Result BasicPitchTranscriptionEngine::transcribePCMFile(
    const std::filesystem::path& pcmFile,
    std::size_t sampleCount,
    double sampleRate,
    const Configuration& configuration,
    const ProgressCallback& progressCallback
)
{
    const auto totalStart = Clock::now();
    Result result;

    if (sampleCount == 0) {
        throw Error(ErrorCode::emptyInput, "Stem audio contains no samples");
    }
    if (!std::isfinite(sampleRate) || std::abs(sampleRate - requiredSampleRate) > 0.01) {
        throw Error(ErrorCode::unsupportedSampleRate, "Basic Pitch requires 22050 Hz mono PCM");
    }
    validateConfiguration(configuration);
    checkCancellation(progressCallback, 0);
    ensureModelLoaded(result.timings);

    std::ifstream stream(pcmFile, std::ios::binary);
    if (!stream.is_open()) {
        throw Error(ErrorCode::audioReadFailed, "Prepared stem audio could not be opened");
    }

    const auto windowSamples = std::max(
        minimumModelSamples,
        static_cast<std::size_t>(std::llround(configuration.windowDurationSeconds * sampleRate))
    );
    const auto overlapSamples = static_cast<std::size_t>(
        std::llround(configuration.overlapDurationSeconds * sampleRate)
    );
    const auto stepSamples = windowSamples - overlapSamples;
    const auto windowCount = sampleCount <= windowSamples
        ? std::size_t {1}
        : 1 + (sampleCount - windowSamples + stepSamples - 1) / stepSamples;

    result.notes.reserve(windowCount * 128);
    const auto inferenceStart = Clock::now();

    for (std::size_t windowIndex = 0; windowIndex < windowCount; ++windowIndex) {
        const auto windowStartSample = std::min(windowIndex * stepSamples, sampleCount);
        const auto readableSamples = std::min(windowSamples, sampleCount - windowStartSample);
        std::vector<float> audio(std::max(readableSamples, minimumModelSamples), 0.0f);

        stream.clear();
        stream.seekg(static_cast<std::streamoff>(windowStartSample * sizeof(float)), std::ios::beg);
        stream.read(
            reinterpret_cast<char*>(audio.data()),
            static_cast<std::streamsize>(readableSamples * sizeof(float))
        );
        if (static_cast<std::size_t>(stream.gcount()) != readableSamples * sizeof(float)) {
            throw Error(ErrorCode::audioReadFailed, "Prepared stem audio ended unexpectedly");
        }
        sanitizeSamples(audio);
        checkCancellation(
            progressCallback,
            (1.0 - progressReservedForPostProcessing) * static_cast<double>(windowIndex)
                / static_cast<double>(windowCount)
        );

        try {
            model_->reset();
            model_->setParameters(
                std::clamp(configuration.noteSensitivity, 0.05f, 0.95f),
                std::clamp(configuration.splitSensitivity, 0.05f, 0.95f),
                std::max(configuration.minimumNoteDurationMilliseconds, 1.0f),
                configuration.includePitchBends
            );
            model_->transcribeToMIDI(audio.data(), static_cast<int>(audio.size()), [&](double localProgress) {
                const auto overall = (
                    static_cast<double>(windowIndex) + std::clamp(localProgress, 0.0, 1.0)
                ) / static_cast<double>(windowCount);
                return !progressCallback
                    || progressCallback((1.0 - progressReservedForPostProcessing) * overall);
            });
        } catch (const Error&) {
            throw;
        } catch (const std::runtime_error& exception) {
            if (std::string(exception.what()) == "transcription_cancelled") {
                throw Error(ErrorCode::cancelled, "Transcription was cancelled");
            }
            throw Error(ErrorCode::inferenceFailed, exception.what());
        } catch (const std::exception& exception) {
            throw Error(ErrorCode::inferenceFailed, exception.what());
        }

        const auto windowStartSeconds = static_cast<double>(windowStartSample) / sampleRate;
        const auto windowEndSeconds = static_cast<double>(windowStartSample + readableSamples) / sampleRate;
        const auto halfOverlapSeconds = configuration.overlapDurationSeconds / 2.0;
        const auto acceptedStart = windowIndex == 0 ? windowStartSeconds : windowStartSeconds + halfOverlapSeconds;
        const auto acceptedEnd = windowIndex + 1 == windowCount
            ? windowEndSeconds
            : windowEndSeconds - halfOverlapSeconds;

        for (const auto& event: model_->getNoteEvents()) {
            Note note {
                event.pitch,
                windowStartSeconds + event.startTime,
                windowStartSeconds + event.endTime,
                event.amplitude,
                event.bends
            };
            if (note.endTimeSeconds <= acceptedStart || note.startTimeSeconds >= acceptedEnd) {
                continue;
            }
            note.startTimeSeconds = std::max(note.startTimeSeconds, acceptedStart);
            note.endTimeSeconds = std::min(note.endTimeSeconds, acceptedEnd);
            result.notes.push_back(std::move(note));
        }
    }

    result.timings.inferenceSeconds = elapsedSeconds(inferenceStart);
    const auto postProcessingStart = Clock::now();
    checkCancellation(progressCallback, 1.0 - progressReservedForPostProcessing);
    stitchNotes(result.notes);
    result.timings.postProcessingSeconds = elapsedSeconds(postProcessingStart);
    result.processedDurationSeconds = static_cast<double>(sampleCount) / sampleRate;
    result.timings.totalSeconds = elapsedSeconds(totalStart);
    checkCancellation(progressCallback, 1);
    return result;
}

} // namespace jammlab::transcription
