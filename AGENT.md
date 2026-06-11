# JammLab Agent Guide

## Project Overview

JammLab is a native macOS SwiftUI app for musicians who practice and analyze local audio/video media. It imports local MP3/WAV audio files and MP4/MOV/M4V video files, plays audio through the app engine, draws a DAW-like peakform timeline, estimates BPM/key locally, supports loop practice, beat-grid alignment, markers, regions, metronome click, pitch shift, speed control, sidecar video following, and project persistence.

The project is an offline-first MVP. Keep the app local-only: no server, no paid APIs, no external audio downloads, and no YouTube integration at this stage.

## Architecture

- `ContentView` renders the main workspace and forwards user actions to `AudioPlayerViewModel`.
- `AudioPlayerViewModel` owns app state, import/open/save flows, playback state, notes, regions, loop range, beat grid settings, timeline navigation, and async task coordination.
- `Services/` contains replaceable boundaries: media import, video audio extraction, approximate analysis, playback, sidecar video following, peakform generation/cache, project documents, recent projects, beat-grid click.
- `Models/` contains stable domain data and pure helpers. Prefer putting reusable time/range logic here.
- `Views/` contains SwiftUI components. Timeline views render state and emit callbacks; they must not mutate project state directly.

## Important Rules

- Do not add network-backed features in the current MVP.
- Keep the offline/local processing approach intact.
- Video import is audio-first: extract the video audio into temporary app media cache while the project is unsaved, persist saved-project video audio into the project-local `media/` directory, use that audio in the existing playback/waveform/stem pipeline, and keep the sidecar `AVPlayer` muted as a follower rather than a sound source.
- Stem separation must not depend on user-installed `pipx`, Python, `audio-separator`, Demucs, `ffmpeg`, `onnxruntime`, `torch`, or `numpy`. Runtime separation goes through bundled `JammLabSeparatorHelper`, which must include the Python runtime, ffmpeg provider, and prefilled model cache for configured separator models.
- Regions are not a separate storage system. A Region is a `TimecodedNote` with `kind == .region`.
- Persist Region as `time + duration`. Do not persist Region `end`; use `regionEndTime` as a computed value.
- Temporary loop range is separate from saved Regions. Editing a temporary loop must not mutate a saved Region. Editing a saved Region must not silently move the temporary loop unless the user explicitly activates that Region as loop.
- Waveform, tempo track, region track, notes, loop markers, beat grid, and playhead must share one visible time range. Use `TimelineViewport` for `time <-> pixel`, zoom, pan, bounds, and intersections.
- Heavy audio work must not run on the main thread. Analysis and peakform generation should stay async/background.
- Do not use system macOS alert/beep sounds for the metronome. Use the app's metronome sound abstraction.
- Keep hotkeys centralized in `AppHotkey`; Help > Keyboard Shortcuts is generated from it.

## Coding Guidelines

- Keep SwiftUI views declarative. Move business rules into ViewModels, Services, or pure Models.
- Prefer small pure helpers for time math, clamping, decoding normalization, and timeline coordinate conversion.
- Put new domain models in `Models/`, app services in `Services/`, app state coordinators in `ViewModels/`, and UI components in `Views/`.
- Put shared visual values in `DesignSystem/AppTheme.swift`. New colors, spacing, radii, font choices, icon sizes, and timeline dimensions should use tokens instead of hardcoded literals.
- When adding a design element with a color, explicitly decide whether the color belongs in Theme Colors settings. If it does, define the default hex and settings group. If it stays local/constant, briefly document why it should not be user-configurable.
- Put reusable UI in `Views/Components/`. Prefer `AppPanel`, `AppSectionTitle`, `AppControlButton`, `JammValueSlider`, and `NoteRowView` before adding local view helpers.
- New interactive controls, including buttons, toggles, sliders, number fields, pickers, and draggable timeline controls, must include a native `.help` tooltip and appropriate accessibility label/value. Reuse `ControlHelpText` for shared copy whenever a matching tooltip exists.
- App value sliders should use the shared `JammValueSlider` path and explicitly provide a `defaultValue`. Do not add direct SwiftUI `Slider` controls for app settings unless a task explicitly needs native macOS slider behavior.
- If a developer asks for an Ableton-style value slider, DAW-style value slider, drag value slider, or compact filled value slider, use the reusable `JammValueSlider` component instead of creating a new custom control from scratch.
- Every `JammValueSlider` instance must explicitly define `defaultValue`, `minValue`, `maxValue`, `step`, `precision`, and `accessibilityLabel`. Set `sensitivity`, `fillColor`, or `displayFormatter` explicitly when the standard drag feel, palette fill, or numeric display is not appropriate.
- If a developer asks for a numeric control, Ableton-style number field, drag-adjustable number field, or DAW-style numeric field, use the reusable `AbletonNumberField` component instead of creating a new custom control from scratch.
- `AbletonNumberField` is a compact macOS numeric control that selects on click without showing an insertion caret, supports drag-up/down adjustment, replacement keyboard entry, Enter commit, Escape rollback, focus-loss commit, and double-click reset to default.
- Every `AbletonNumberField` instance must explicitly define `defaultValue`, `minValue`, `maxValue`, `step`, `precision`, and `accessibilityLabel`. Set `sensitivity` explicitly when the standard drag feel is not appropriate.
- If `defaultValue`, `minValue`, or `maxValue` are not specified for a new numeric field, first look for existing constraints in the relevant model or ViewModel. If they are not present, ask the user/developer instead of inventing values silently.
- Example: `AbletonNumberField(value: $tempo, minValue: 40, maxValue: 240, defaultValue: AppDefaults.defaultTempoBPM, step: 1, sensitivity: 0.25, precision: 0, accessibilityLabel: "Tempo")`.
- Keep `ContentView` as a thin shell. Main workspace panel composition belongs in `Views/MainWorkspacePanels.swift`; feature-specific reusable controls belong in `Views/Components/`.
- Before changing UI, identify the owning component: `TopToolbarView` for global toolbar, `WaveformTimelineView` for timeline/stem lanes and no-file import prompt, `InspectorSidebarView` for notes/markers/regions, and `TransportBarView`/`TransportControlsView` for playback controls.
- Do not mix visual refactors with playback/audio architecture changes. Styling-only work should not change `AudioPlayerViewModel` public API without a clear reason.
- Avoid new hardcoded `Color(...)`, `.padding(16)`, `cornerRadius: 8`, fixed timeline heights, or repeated font definitions in views. If a value is part of the app style, add a semantic token first.
- Do not make broad visual redesigns in one pass. Prefer structural container cleanup, reusable components, and token extraction before changing the overall look.
- Use async/await for file/audio work. Cancel stale tasks when importing or opening a different project.
- Errors shown to users should be actionable and should not leave partially updated state.
- Avoid duplicate sources of truth. Do not store computed musical positions if absolute audio time can be converted through beat-grid settings.
- Prefer conservative refactors. Do not rewrite the audio engine, renderer, or UI unless the requested task needs it.

## Timeline Rules

- Timeline navigation is based on `TimelineViewport(duration:visibleRange:)`.
- All timeline layers must use the same visible range for rendering and interaction.
- Zoom changes visible duration; horizontal scroll pans visible range. Neither should change absolute note, region, loop, or playback times.
- Convert time to pixel with `TimelineViewport.xPosition(for:width:)`.
- Convert pixel to time with `TimelineViewport.time(forX:width:)`.
- Clip overlays through `TimelineViewport.intersection(start:end:)`.
- Future snapping, zoom-to-selection, follow-playhead, and minimap work should build on the same viewport model.

## Audio Rules

- Playback uses `MultiTrackAudioPlayer`, a unified `AVAudioEngine` path for original audio, stems, pitch/rate, and click.
- Keep `AudioPlaybackControlling` as the ViewModel-facing playback boundary; avoid adding direct `AVAudioEngine` calls to UI or ViewModel code.
- Playback clock in `AudioPlayerViewModel` is the source for UI time. Click scheduling belongs inside the playback engine, not in UI refresh loops.
- Peakform generation is handled by `CachedPeakformProvider`. It decodes audio once, downmixes to mono, creates multi-resolution min/max/rms levels for `samplesPerPeak` values `[128, 256, 512, 1024, 2048, 4096]`, and caches one v2 `.peakform` binary file under `Application Support/JammLab/PeakformCache` for unsaved projects and legacy fallback. Saved projects should persist project-specific peakforms through `ProjectArtifactStore` in the project-local `peaks/` directory.
- Corrupted, old, or incompatible peakform cache files should be ignored and regenerated. Do not add audio-side legacy `.peakform` cache lookup next to the source audio file.
- Saved-project artifacts live next to the `.jammlab` file: `stems/` for separated stem WAV files and `metadata.json`, `peaks/` for peakform binaries, and `media/` for extracted video audio. Default Save As should select/create the project folder and open sandbox security-scoped access on that folder. `StemModels` remains a shared backend dependency cache in Application Support, not a project artifact.
- `JammLabStemHelper` is the Swift job watcher for `StemJobs`, heartbeat, cancellation, and cache normalization. Do not move that IPC flow into Python unless explicitly requested.
- `JammLabSeparatorHelper` is the bundled PyInstaller one-dir Python backend. Build it with `scripts/build_separator_helper.sh`; the script prefetches separator models into the bundled cache, and Xcode only copies the already-built artifact into `Contents/Resources/JammLabSeparatorHelper`.
- Keep stem job directories versioned through `StemJobFiles.helperVersion` when changing helper protocol or backend visibility, so stale helper processes cannot process new jobs.

## Persistence

- Project files are JSON `.jammlab` documents.
- Audio access uses security-scoped bookmarks.
- Recent projects are stored in user defaults and capped to 10 entries.
- Project load must normalize/clamp duration-dependent state: beat grid, loop range, notes, regions, playback rate, pitch shift, and tempo.

## Future Roadmap

- Better BPM/key detection with stronger DSP or Core ML.
- Chord detection and chord markers.
- Stem export, backend diagnostics, and packaged separator hardening.
- Advanced zoom, zoom-to-selection, follow playhead, minimap.
- Beat-grid snapping improvements and quantize tools.
- Metronome count-in, subdivisions, sound presets, and MIDI output.
