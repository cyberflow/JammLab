# JammLab

JammLab is a native macOS practice app for importing local audio or video,
building a timeline, marking song sections, looping difficult parts, and
separating stems locally.

The app is local-first: playback, waveform rendering, project files, stem
separation jobs, and video-audio extraction run on the user's Mac. JammLab does
not require a server, paid API, cloud upload, or user-installed
`audio-separator` runtime.

## Features

- Import local audio files: MP3 and WAV.
- Import local video files: MP4, MOV, and M4V.
- Extract video audio to M4A for the normal audio pipeline.
- Open an optional muted Video Window from the View menu; audio playback remains
  the source of truth.
- DAW-style transport with play, pause, stop, seek, speed, and pitch controls.
- Waveform timeline with dynamic beat grid, zoom/scroll controls, and playhead.
- Notes, markers, and colored regions for section-based practice.
- Loop region editing with audio-engine loop execution.
- Click, Snap, and editable time signature controls.
- Global Settings for theme colors, click sound, stem backend compute mode, and
  audio input/output device preferences.
- Local stem separation through bundled helper processes.
- Project-local artifacts for saved projects: `stems/`, `peaks/`, and `media/`
  live next to the `.jammlab` project file.
- Undo/redo for project edits and modified-project save prompts.

## Development

JammLab is a native macOS SwiftUI application. See
[CONTRIBUTING.md](CONTRIBUTING.md) for local setup, verification commands, and
bundled separator helper build instructions.

Before a normal app build, create the bundled separator artifact with
`scripts/build_separator_helper.sh`. The `JammLab` target copies it from
`build/JammLabSeparatorHelper/dist/JammLabSeparatorHelper` into
`JammLab.app/Contents/Resources/JammLabSeparatorHelper`. Test workflows that do
not need the packaged helper may set `SKIP_BUNDLED_SEPARATOR_HELPER=1`.

GitHub CI uses these modes:

- feature branches and pull requests to `main`: Python helper tests and Swift tests;
- `main` pushes: tests plus unsigned Debug/Release build smoke;
- stable release tags `vMAJOR.MINOR.PATCH`: tests, bundled separator build,
  unsigned Release app build, DMG packaging, source archive upload, and a
  published latest GitHub Release with downloadable assets;
- beta release tags `vMAJOR.MINOR.PATCH-beta`: the same artifact build, published
  as a GitHub prerelease and not marked latest;
- development tags `vMAJOR.MINOR.PATCH-dev.N`: the same artifact build, uploaded
  only as workflow artifacts. Dev tags do not create GitHub Releases.

Release versions are derived from Git tags. Tags such as `v0.1.0`,
`v0.1.0-beta`, and `v0.1.0-dev.1` all build the app with
`MARKETING_VERSION=0.1.0`; the standard macOS About panel reads that base app
version from the generated app `Info.plist`. The tag suffix is used only for the
release channel and artifact names. GitHub release notes are generated
automatically for stable and beta releases. Re-running a tag workflow replaces
release assets with the same names, while workflow artifacts remain available
for build debugging.

## Stem Separation

Stem separation runs through two bundled helpers:

- `JammLabStemHelper`: a Swift job watcher that owns heartbeat, cancellation,
  cache, and job status protocol.
- `JammLabSeparatorHelper`: a PyInstaller-packaged Python runtime that wraps
  `audio-separator`.

No user-installed `pipx`, Python, `audio-separator`, Demucs, `ffmpeg`,
`onnxruntime`, `torch`, or `numpy` runtime is required. The packaged separator
includes its Python runtime, FFmpeg provider, and a prefilled model cache for
the configured separator models. At runtime JammLab seeds
`Application Support/JammLab/StemModels` from the bundled cache before
separation.

Stem separation is an offline background job and can take a while on longer
tracks.

## Project Artifacts

Unsaved projects use app cache as temporary staging storage. After a project is
saved, project-specific artifacts move next to the project file:

```text
Song/
  Song.jammlab
  stems/
  peaks/
  media/
```

- `stems/` stores separated stem WAV files and metadata.
- `peaks/` stores main and stem peakform cache files.
- `media/` stores extracted video audio such as `audio.m4a`.

The shared separator model cache remains under Application Support because it is
a backend dependency, not a project artifact.

## Design Philosophy

JammLab favors a compact, audio-first workflow over a large editing surface.
The main audio engine owns transport time, playback state, loop execution, and
click timing. UI views display the audio clock and send explicit editing
commands; they do not drive playback timing themselves.

The interface follows a DAW-inspired style: dense controls, minimal chrome,
drag-adjustable numeric fields, compact value sliders, and editable theme
colors. Project state is portable when saved as a project folder, while global
preferences such as app colors, audio devices, and click sound settings stay in
application settings.

## Project Structure

```text
JammLab/
  Models/
  Services/
  ViewModels/
  Views/
  DesignSystem/
  Utilities/
JammLabStemHelper/
JammLabSeparatorHelper/
Configurations/
scripts/
docs/
```

The app uses SwiftUI + MVVM with a service layer and focused pure logic models.
`AudioPlayerViewModel` coordinates import/open/save, playback state, project
edits, stems, video follower state, and undo/dirty tracking. Timeline rendering
uses `TimelineViewport` as the shared time-to-pixel model so waveform, beat
grid, regions, markers, loop handles, and playhead stay synchronized.

## Approximate Analysis

- BPM is estimated from a short-time RMS energy envelope and autocorrelation.
- Key is estimated from a Goertzel-based pitch-class chroma and
  Krumhansl-style major/minor profile matching.
- Waveform rendering uses cached multi-resolution min/max/rms peakform data.

The analysis is intentionally lightweight and local. It is useful for practice
workflow hints, not as a replacement for a full music-information-retrieval
pipeline.

## License

JammLab is released under the MIT License. See [LICENSE](LICENSE).

Third-party runtime and build dependency notices are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
