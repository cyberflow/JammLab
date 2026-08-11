# Changelog

All notable changes to JammLab will be documented in this file.

This project follows tag-based release versioning. Stable releases use tags in
the form `vMAJOR.MINOR.PATCH`, beta releases use `vMAJOR.MINOR.PATCH-beta`, and
development artifact builds use `vMAJOR.MINOR.PATCH-dev.N`.

## Unreleased

## 1.2.0

### New Features

- Added fully offline per-stem Audio-to-MIDI transcription with the bundled Basic Pitch model, cancellable progress, polyphonic Notation and MIDI tracks, project persistence, and MIDI export. Drum stems remain excluded, and re-transcription warns before replacing existing notes and rests.
- Added polyphonic Notation and MIDI editing with chords, overlapping durations, chord-aware layout, mouse movement and resizing, automatic page turns, tied long notes, and a persistent per-Stem piano-roll display.
- Expanded Notation entry and editing with pitched notes and rests, ledger-line pitches from G3 through D6, sixteenth notes, augmentation dots, cross-measure ties, keyboard shortcuts, drag and arrow-key pitch editing, and measure-content deletion that preserves harmony.
- Added inline flats, naturals, and sharps plus automatic rhythmic beaming for eighth and sixteenth notes, with Leland glyphs, shared stem directions, secondary beam breaks, beamlets, persistence, and MusicXML export.
- Added multi-part Stem notation with collapsible tracks, aligned score systems, part visibility, Region labels, instrument metadata, selected-part MusicXML export, Drum Clef with a 16-sound GM palette, and octave-down Bass 8 clef.
- Added a bar-and-beat position readout to the transport time display.
- Added automatic update checks for stable releases, with GitHub release notes, download links, remind-later behavior, and per-version skipping while development and beta builds remain offline.

### Improvements

- Moved audio and Stem playback preparation off the main thread with cancellable progress, safer memory limits, and transactional project and mode switching that keeps the current audio available if preparation fails.
- Hardened the bundled Stem helper with the versioned v6 job protocol, startup capability checks, stale-helper diagnostics, and a validated manifest for bundled models and compute modes.
- Improved Notation measure and system spacing to keep visible parts aligned, prevent late notes from overstretching measures, backfill final pages, and avoid unnecessary one-measure rows.
- Refined the Notation workspace with clearer tooltips and numpad shortcuts, vertical scrolling for expanded tracks, consistent Rest and track controls, and aligned Stem Mute and Solo buttons.

### Fixes

- Corrected flats, naturals, and sharps produced by automatic Stem transcription so they follow the key signature and common-practice measure rules.
- Fixed Leland flags separating from stems when rendering short notes in chords and Drum notation.
- Prevented saved-video cleanup from deleting folders outside JammLab's temporary media cache.
- Preserved later notes and rests when changing to an oversized Notation duration, and recomposed rests safely when removing selected notes.
- Fixed multi-part accessibility selection announcements and kept harmony editing from clearing the selected Stem note.

## 1.1.0

### New Features

- Added a MusicXML-ready Notation track with synced staff measures, persisted harmony editing, adaptive measure fitting, and editable project key/mode selectors backed by auto-detected tonal metadata.
- Added a synced Notation window that opens from the View menu or Notation track context menu and shares harmony editing with the main timeline.
- Added MusicXML export for Notation from the File menu and Notation window, including export metadata, project tempo markings, Region labels, harmony symbols, note types, and split-rest durations.
- Added Notation measure range selection with Shift-click, Cmd+C/Cmd+V copy and replace-paste for harmony contents, and Esc to clear the selection.
- Added Notation clicks for moving the playback position marker from measure selections and barlines in both the main track and Notation window.

### Improvements

- Improved timeline and Notation playback responsiveness and reduced idle CPU use in loaded projects.

### Validation

- Swift tests passed: `SKIP_BUNDLED_SEPARATOR_HELPER=1 xcodebuild test -quiet -project JammLab.xcodeproj -scheme JammLab -destination 'platform=macOS,arch=arm64' -derivedDataPath build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= ONLY_ACTIVE_ARCH=YES ARCHS=arm64`.
- Performance tests passed: `SKIP_BUNDLED_SEPARATOR_HELPER=1 xcodebuild test -quiet -project JammLab.xcodeproj -scheme JammLabPerformance -destination 'platform=macOS,arch=arm64' -derivedDataPath build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= ONLY_ACTIVE_ARCH=YES ARCHS=arm64`.
- Release metadata check passed: `scripts/derive_release_metadata.sh v1.1.0` returned stable release metadata with app version `1.1.0`.

## 1.0.1

### New Features

- Added an optional six-stem separation method with guitar and piano tracks.

### Improvements

- Automatically switch to stem playback after stem separation completes.
- Added a tuner input signal meter to show incoming audio before pitch is detected.
- Made the tuner detect quieter notes and keep the last detected note visible briefly.
- Cleaned up Settings sidebar order and focus styling, aligned Audio device pickers, and made the Audio reset button restore both input and output devices.

### Fixes

- Made region activation from the inspector and timeline set the loop and position marker without interrupting active playback.

### Validation

- Python helper tests passed: `python3 -m unittest JammLabSeparatorHelper/test_runner.py` ran 10 tests with 0 failures.
- Swift tests passed: `SKIP_BUNDLED_SEPARATOR_HELPER=1 xcodebuild test -project JammLab.xcodeproj -scheme JammLab -destination 'platform=macOS,arch=arm64' -derivedDataPath build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= ONLY_ACTIVE_ARCH=YES ARCHS=arm64` ran 250 tests with 0 failures.
- Release metadata check passed: `scripts/derive_release_metadata.sh v1.0.1` returned stable release metadata with app version `1.0.1`.

## 1.0.0

### Highlights

- Local-first macOS practice workspace for importing audio or video, building a timeline, marking song sections, looping difficult passages, and practicing with speed and pitch controls.
- Audio-first video workflow that extracts video audio for playback while keeping a muted sidecar video window synchronized with the app transport.
- Offline stem separation through bundled helper processes, with no user-installed Python, Demucs, FFmpeg, ONNX Runtime, Torch, NumPy, or `audio-separator` required at runtime.
- DAW-style timeline with waveform rendering, beat grid, notes, markers, colored regions, loop editing, playback marker behavior, and saved zoom and scroll state.

### New Features

- Import local MP3/WAV audio and MP4/MOV/M4V video files.
- Save and reopen `.jammlab` projects with project-local `stems/`, `peaks/`, and `media/` artifacts.
- Add notes, markers, colored regions, loop regions, tempo/time-signature markers, and beat-grid snapping.
- Adjust playback speed and pitch independently for practice.
- Use a live chromatic tuner window with selected audio input device support and low bass note detection down to A0.
- Choose stem separation methods, including a two-stem vocals/instrumental option.
- Persist playback marker position, timeline viewport, and video window state in saved projects.
- Configure theme colors, click sound, stem backend compute mode, and audio input/output devices.

### Improvements

- Keep the playhead visible while playing in a zoomed timeline and return the view to the saved playback marker when playback stops.
- Move the playback marker to a region start on region double-click without activating that region as a loop.
- Reduce repeated per-window allocation during track pitch analysis.
- Package stable release tags as unsigned DMG and source archive assets through GitHub Actions.

### Fixes

- Limit microphone permission requests to tuner use.
- Honor the selected audio input device in the tuner and restart correctly when the input device changes while the tuner is running.
- Remove an unwanted focus ring from the tuner toolbar.
- Clarify the inspector all-items filter label.

### Known Limitations

- Release artifacts are unsigned; users may need to allow the app manually in macOS security settings.
- JammLab is local-only for v1.0.0: no cloud sync, server features, paid APIs, YouTube integration, or external audio downloads.
- BPM and key detection are lightweight local estimates intended for practice, not replacements for full music-analysis tools.
- Stem separation runs as an offline background process and can take time on longer tracks.
- JammLab targets macOS 14.0 or newer.

### Validation

- Python helper tests passed: `python3 -m unittest JammLabSeparatorHelper/test_runner.py` ran 7 tests with 0 failures.
- Swift tests passed: `SKIP_BUNDLED_SEPARATOR_HELPER=1 xcodebuild test -project JammLab.xcodeproj -scheme JammLab -destination 'platform=macOS,arch=arm64' -derivedDataPath build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= ONLY_ACTIVE_ARCH=YES ARCHS=arm64` ran 209 tests with 0 failures.
- Release tag workflow is expected to build the bundled separator helper, unsigned Release app, unsigned DMG, and source archive when the future `v1.0.0` tag is pushed.

## 0.1.0-beta

- Internal beta release automation marker before the first public stable release.
