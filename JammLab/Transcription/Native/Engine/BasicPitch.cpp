//
// Created by Damien Ronssin on 10.03.23.
//

#include "BasicPitch.h"

#include <algorithm>
#include <stdexcept>

BasicPitch::BasicPitch(const std::filesystem::path& modelDirectory)
    : mFeaturesCalculator(modelDirectory / "features_model.ort")
    , mBasicPitchCNN(modelDirectory)
{
}

void BasicPitch::reset()
{
    mBasicPitchCNN.reset();
    mNotesCreator.clear();

    mContoursPG.clear();
    mContoursPG.shrink_to_fit();
    mNotesPG.clear();
    mNotesPG.shrink_to_fit();
    mOnsetsPG.clear();
    mOnsetsPG.shrink_to_fit();
    mNoteEvents.clear();
    mNoteEvents.shrink_to_fit();

    mNumFrames = 0;
}

void BasicPitch::setParameters(
    float inNoteSensitivity,
    float inSplitSensitivity,
    float inMinNoteDurationMs,
    bool includePitchBends
)
{
    mParams.frameThreshold = 1.0f - inNoteSensitivity;
    mParams.onsetThreshold = 1.0f - inSplitSensitivity;

    mParams.minNoteLength =
        static_cast<int>(std::round(inMinNoteDurationMs / 1000.0f / (FFT_HOP / BASIC_PITCH_SAMPLE_RATE)));

    mParams.pitchBend = includePitchBends ? MultiPitchBend : NoPitchBend;
    mParams.melodiaTrick = true;
    mParams.inferOnsets = true;
}

void BasicPitch::transcribeToMIDI(
    float* inAudio,
    int inNumSamples,
    const ProgressCallback& progressCallback
)
{
    if (inAudio == nullptr || inNumSamples <= 0) {
        throw std::invalid_argument("Basic Pitch audio input is empty");
    }
    if (progressCallback && !progressCallback(0)) {
        throw std::runtime_error("transcription_cancelled");
    }

    const float* stacked_cqt = mFeaturesCalculator.computeFeatures(inAudio, inNumSamples, mNumFrames);
    if (mNumFrames == 0) {
        mNoteEvents.clear();
        return;
    }
    if (progressCallback && !progressCallback(0.15)) {
        throw std::runtime_error("transcription_cancelled");
    }

    mOnsetsPG.resize(mNumFrames, std::vector<float>(static_cast<size_t>(NUM_FREQ_OUT), 0.0f));
    mNotesPG.resize(mNumFrames, std::vector<float>(static_cast<size_t>(NUM_FREQ_OUT), 0.0f));
    mContoursPG.resize(mNumFrames, std::vector<float>(static_cast<size_t>(NUM_FREQ_IN), 0.0f));

    mOnsetsPG.shrink_to_fit();
    mNotesPG.shrink_to_fit();
    mContoursPG.shrink_to_fit();

    mBasicPitchCNN.reset();

    const size_t num_lh_frames = BasicPitchCNN::getNumFramesLookahead();

    std::vector<float> zero_stacked_cqt(NUM_HARMONICS * NUM_FREQ_IN, 0.0f);

    // Run the CNN with 0 input and discard output (only for num_lh_frames)
    for (int i = 0; i < num_lh_frames; i++) {
        mBasicPitchCNN.frameInference(zero_stacked_cqt.data(), mContoursPG[0], mNotesPG[0], mOnsetsPG[0]);
    }

    // Run the CNN with real inputs and discard outputs (only for num_lh_frames)
    for (size_t frame_idx = 0; frame_idx < num_lh_frames; frame_idx++) {
        mBasicPitchCNN.frameInference(
            stacked_cqt + frame_idx * NUM_HARMONICS * NUM_FREQ_IN, mContoursPG[0], mNotesPG[0], mOnsetsPG[0]);
    }

    // Run the CNN with real inputs and correct outputs
    for (size_t frame_idx = num_lh_frames; frame_idx < mNumFrames; frame_idx++) {
        mBasicPitchCNN.frameInference(stacked_cqt + frame_idx * NUM_HARMONICS * NUM_FREQ_IN,
                                      mContoursPG[frame_idx - num_lh_frames],
                                      mNotesPG[frame_idx - num_lh_frames],
                                      mOnsetsPG[frame_idx - num_lh_frames]);
        if (progressCallback && (frame_idx % 32 == 0)) {
            const auto progress = 0.15 + 0.75 * static_cast<double>(frame_idx) / static_cast<double>(mNumFrames);
            if (!progressCallback(progress)) {
                throw std::runtime_error("transcription_cancelled");
            }
        }
    }

    // Run end with zeroes as input and last frames as output
    for (size_t frame_idx = mNumFrames; frame_idx < mNumFrames + num_lh_frames; frame_idx++) {
        mBasicPitchCNN.frameInference(zero_stacked_cqt.data(),
                                      mContoursPG[frame_idx - num_lh_frames],
                                      mNotesPG[frame_idx - num_lh_frames],
                                      mOnsetsPG[frame_idx - num_lh_frames]);
    }

    mNoteEvents = mNotesCreator.convert(mNotesPG, mOnsetsPG, mContoursPG, mParams, true);
    if (progressCallback && !progressCallback(1)) {
        throw std::runtime_error("transcription_cancelled");
    }
}

void BasicPitch::updateMIDI()
{
    mNoteEvents = mNotesCreator.convert(mNotesPG, mOnsetsPG, mContoursPG, mParams, false);
}

const std::vector<Notes::Event>& BasicPitch::getNoteEvents() const
{
    return mNoteEvents;
}
