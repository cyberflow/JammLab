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

Use the exact arm64 CPython version in `JammLabSeparatorHelper/.python-version`
(currently 3.14.5), setting `PYTHON_BIN` if necessary. The build rejects other
Python versions and platforms before changing build output. CI uses
`actions/setup-python` with the same version file.

Each helper build creates a fresh venv and installs all 69 pinned runtime and
packaging dependencies from `requirements-macos-arm64.lock`. It runs `pip check`
and checks the complete installed inventory against the lock. No dependency is
automatically upgraded. `build-constraints.txt` also pins tools used in isolated
source builds. The first build needs network access to obtain packages and
models. Later builds cache package downloads/wheels and model files, never the
venv or PyInstaller build state. This fixes package versions, not the bytes of
the final signed binary or DMG; macOS/Xcode runner images can still change.

### Updating the dependency lock

1. Start a dedicated branch. Use the pinned Python and create an isolated
   candidate venv under `build/`; do not freeze a general-purpose environment.
2. Install the current lock there first. Make intentional edits to the direct
   requirements and, if needed, the Python version/build constraints. Resolve
   those edits in the candidate environment with pip, explicitly selecting
   intended upgrades. Keep `setuptools<82` compatibility until separately tested.
3. Run `pip check` in the candidate environment and inspect the full dependency
   diff. Export `python -m pip freeze --all` from that environment to
   `JammLabSeparatorHelper/requirements-macos-arm64.lock`. Keep exact pins for
   pip, setuptools, wheel, Cython and packaging hooks. `onnx-weekly` is required
   by audio-separator 0.44.2 and is pinned to its existing development release;
   do not replace it with `onnx` as part of a routine lock refresh.
4. Align `build-constraints.txt` with the candidate versions, then run
   `python3 scripts/check_separator_dependencies.py --refresh-input-digest`.
   The digest records all direct inputs and detects stale locks; it does not
   certify dependency compatibility.
5. Build from scratch with `scripts/build_separator_helper.sh`, run the offline
   smoke tests below, and update THIRD_PARTY_NOTICES.md from the resulting
   environment. CI must pass both a cold and a warm run before merging.

### Packaging validation

```sh
python3 scripts/check_separator_dependencies.py --check-platform
python3 -m unittest discover -s scripts -p 'test_separator_dependencies.py'
build/JammLabSeparatorHelper/venv/bin/python scripts/smoke_separator_helper.py \
  build/JammLabSeparatorHelper/dist/JammLabSeparatorHelper/JammLabSeparatorHelper \
  --report-dir build/JammLabSeparatorHelper/reports/standalone
```

The smoke test uses macOS `sandbox-exec` to deny networking, a fresh home/temp
directory and a PATH containing no external Python or FFmpeg. It verifies the
sandbox restriction, helper capabilities and environment, then separates a
deterministic ten-second WAV with every manifest model on CPU. It checks stem
names/counts, readable finite samples and duration within 100 ms. This checks
packaging, not musical quality. CI repeats it against the helper inside the
Release app, verifies the DMG, and verifies SHA-256 checksums after downloading
the DMG and source ZIP in a separate job. Logs and timings are uploaded even on
failure. Run only on a macOS host that permits the sandbox to be applied.

PRs touching the helper, related scripts or workflows run full packaging checks;
UI-only PRs keep the fast checks. Tags and manual runs always validate packaging.
Use the manual `disable_caches` option for cold verification, then rerun with
caches enabled. Manual validation never publishes a release, even on a tag.

Useful paths and settings:

- Project virtual environment: `build/JammLabSeparatorHelper/venv`.
- Model cache: `build/JammLabSeparatorHelper/model-cache`.
- PyInstaller output: `build/JammLabSeparatorHelper/dist/JammLabSeparatorHelper`.
- Python executable override: `PYTHON_BIN=/path/to/python3`.
- Default prefetched models: `htdemucs.yaml`, `htdemucs_6s.yaml`, and `UVR-MDX-NET-Inst_HQ_5.onnx`.
- `JammLabSeparatorHelper/helper-manifest.json` is the single source of truth for supported models, required cache files, compute modes, and helper protocol compatibility.

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
