# Native Basic Pitch transcription provenance

JammLab's transcription module was extracted from these upstream revisions:

- NeuralNote: `f979e51dfeab54d5921858af39403308ab06e60c`
- Spotify Basic Pitch: `fa5997af0a8210982619003269994a1be25eddf3`
- RTNeural: `2ca066e5e529ea3ed4120c368ee16526eeaf2cec`
- ONNX Runtime: `c57cf374b67f72575546d7b4c69a1af4972e2b54` (`v1.14.1`)
- nlohmann/json: `3.11.1`

## Extracted components

The files in `Native/Engine` derive from NeuralNote's `Lib/Model` directory:

- `BasicPitch.*` — inference orchestration;
- `BasicPitchCNN.*` — RTNeural CNN inference;
- `Features.*` — CQT and harmonic-stacking feature inference;
- `Notes.*` — polyphonic note-event and optional pitch-bend decoding;
- `BasicPitchConstants.h` and `Utils.h` — model constants and small helpers.

The four JSON CNN weight files and `features_model.ort` in
`Resources/BasicPitchModel` derive from NeuralNote's `Lib/ModelData` and
release model archive. NeuralNote documents those files as its adapted native
execution of Spotify Basic Pitch.

## JammLab adaptations

- Removed JUCE, BinaryData, plugin, UI, MIDI-file, and test-export dependencies.
- Resolve all model data through the application bundle.
- Use RTNeural's STL backend and an arm64-only static ONNX Runtime build.
- Added typed errors, lazy model reuse, bounded window reads, window stitching,
  structured notes, progress, and cooperative cancellation.
- Moved audio decoding/resampling, project-time mapping, quantization,
  Notation/MIDI conversion, persistence, and UI state into Swift layers.

No Python, shell command, helper process, AU/VST host, or network model download
is used by the production transcription path.
