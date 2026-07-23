#pragma once

#include <cstddef>
#include <filesystem>
#include <functional>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

class BasicPitch;

namespace jammlab::transcription
{

enum class ErrorCode {
    emptyInput,
    unsupportedSampleRate,
    audioReadFailed,
    modelResourceMissing,
    modelInitializationFailed,
    inferenceFailed,
    invalidModelOutput,
    cancelled
};

class Error final : public std::runtime_error
{
public:
    Error(ErrorCode code, const std::string& message);

    [[nodiscard]] ErrorCode code() const noexcept;

private:
    ErrorCode code_;
};

struct Configuration {
    float noteSensitivity = 0.7f;
    float splitSensitivity = 0.5f;
    float minimumNoteDurationMilliseconds = 125.0f;
    bool includePitchBends = false;
    double windowDurationSeconds = 30.0;
    double overlapDurationSeconds = 2.0;
};

struct Note {
    int pitch = 0;
    double startTimeSeconds = 0;
    double endTimeSeconds = 0;
    double confidence = 0;
    std::vector<int> pitchBends;
};

struct Timings {
    double modelLoadSeconds = 0;
    double inferenceSeconds = 0;
    double postProcessingSeconds = 0;
    double totalSeconds = 0;
};

struct Result {
    std::vector<Note> notes;
    double processedDurationSeconds = 0;
    std::vector<std::string> warnings;
    Timings timings;
};

using ProgressCallback = std::function<bool(double)>;

class BasicPitchTranscriptionEngine final
{
public:
    static constexpr double requiredSampleRate = 22050.0;

    explicit BasicPitchTranscriptionEngine(std::filesystem::path modelDirectory);
    ~BasicPitchTranscriptionEngine();

    BasicPitchTranscriptionEngine(const BasicPitchTranscriptionEngine&) = delete;
    BasicPitchTranscriptionEngine& operator=(const BasicPitchTranscriptionEngine&) = delete;

    Result transcribePCMFile(
        const std::filesystem::path& pcmFile,
        std::size_t sampleCount,
        double sampleRate,
        const Configuration& configuration,
        const ProgressCallback& progressCallback = {}
    );

private:
    void ensureModelLoaded(Timings& timings);

    std::filesystem::path modelDirectory_;
    std::unique_ptr<BasicPitch> model_;
};

} // namespace jammlab::transcription
