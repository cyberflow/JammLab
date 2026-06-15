# Contributing

This guide covers the local development workflow for JammLab contributors.
JammLab is a native macOS SwiftUI app with a bundled Python separator helper.

## Development Environment

- macOS deployment target: `14.0`.
- Verified local toolchain: Xcode `26.5` (`17F42`).
- Main project: `JammLab.xcodeproj`.
- Main scheme: `JammLab`.
- Build configurations are backed by `Configurations/*.xcconfig`.

Run the app locally:

```sh
open JammLab.xcodeproj
```

Then select the `JammLab` scheme, choose `My Mac`, and press `Cmd+R`.

Run the main verification commands:

```sh
xcodebuild test -project JammLab.xcodeproj -scheme JammLab -destination 'platform=macOS' -derivedDataPath build
python3 -m unittest JammLabSeparatorHelper/test_runner.py
```

For a CI-style unsigned Release build smoke test:

```sh
xcodebuild build -project JammLab.xcodeproj -scheme JammLab -configuration Release -destination 'platform=macOS' -derivedDataPath build-ci -xcconfig Configurations/CI.xcconfig
```

Performance tests live in the separate `JammLabPerformance` scheme. They are
manual-only benchmarks and are not part of the normal test workflow.

GitHub CI uses contributor-facing checks for Python helper tests, Swift tests,
and unsigned app build smoke runs. Release tag workflows also build the bundled
separator helper and package unsigned artifacts.

## Bundled Separator Helper

Stem separation runs through two bundled helpers:

- `JammLabStemHelper`: a Swift job watcher that owns heartbeat, cancellation,
  cache, and job status protocol.
- `JammLabSeparatorHelper`: a PyInstaller-packaged Python runtime that wraps
  `audio-separator`.

Runtime stem separation must not depend on user-installed `pipx`, Python,
`audio-separator`, Demucs, `ffmpeg`, `onnxruntime`, `torch`, or `numpy`. The app
uses the bundled helper, bundled FFmpeg provider, and the seeded model cache.

Build the helper from the repository root before building the app target:

```sh
scripts/build_separator_helper.sh
```

The first helper build installs Python dependencies and prefetches separator
models, so it requires network access. Later runs reuse project-local build
state under `build/JammLabSeparatorHelper/`.

Useful paths and settings:

- Project virtual environment: `build/JammLabSeparatorHelper/venv`.
- Model cache: `build/JammLabSeparatorHelper/model-cache`.
- PyInstaller output: `build/JammLabSeparatorHelper/dist/JammLabSeparatorHelper`.
- Python executable override: `PYTHON_BIN=/path/to/python3`.
- Prefetched model list override: `SEPARATOR_MODELS="htdemucs.yaml other.yaml"`.

The `JammLab` target copies
`build/JammLabSeparatorHelper/dist/JammLabSeparatorHelper` into
`JammLab.app/Contents/Resources/JammLabSeparatorHelper`. If that artifact is
missing, Xcode fails with an explicit build error. Test workflows may set
`SKIP_BUNDLED_SEPARATOR_HELPER=1` when they do not need the packaged helper.

## Running audio-separator Locally

Use the project-created virtual environment and the JammLab wrapper. This keeps
local manual runs close to the production path because
`JammLabSeparatorHelper/runner.py` imports and drives
`audio_separator.separator.Separator`.

First create or update the project environment:

```sh
scripts/build_separator_helper.sh
```

Print wrapper diagnostics:

```sh
build/JammLabSeparatorHelper/venv/bin/python JammLabSeparatorHelper/runner.py --env_info
```

Prefetch a model into the project cache:

```sh
build/JammLabSeparatorHelper/venv/bin/python JammLabSeparatorHelper/runner.py --prefetch_model htdemucs.yaml --model_file_dir build/JammLabSeparatorHelper/model-cache
```

Run a local separation smoke test from the repository root:

```sh
mkdir -p build/JammLabSeparatorHelper/local-output
build/JammLabSeparatorHelper/venv/bin/python JammLabSeparatorHelper/runner.py path/to/input.wav --output_dir build/JammLabSeparatorHelper/local-output --model_file_dir build/JammLabSeparatorHelper/model-cache -m htdemucs.yaml --output_format WAV --compute_device cpu
```

Replace `path/to/input.wav` with a local audio file. Generated smoke-test output
belongs under `build/JammLabSeparatorHelper/` and should not be committed.
