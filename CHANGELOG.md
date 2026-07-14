# Changelog

All notable changes to JammLab will be documented in this file.

This project follows tag-based release versioning. Stable releases use tags in
the form `vMAJOR.MINOR.PATCH`, beta releases use `vMAJOR.MINOR.PATCH-beta`, and
development artifact builds use `vMAJOR.MINOR.PATCH-dev.N`.

## Unreleased

- Added Notation note-entry mode for placing pitched notes with Leland-rendered note glyphs, note selection preview, cross-rest insertion, rest recomposition, and MusicXML export.
- Expanded Notation entry to ledger-line pitches from G3 through D6 and added rest-entry controls for inserting selected rest durations.
- Added Notation note editing for dragging note pitch, arrow-key pitch changes, and deleting selected notes back to rests.
- Added per-stem Notation parts with collapsible stem notation tracks, score-aligned multi-part Notation systems, shared Region labels, part visibility controls, and multi-part MusicXML export.
- Added clearer hover tooltips and numpad shortcuts for Notation duration buttons.
- Added a bar/beat position readout to the transport time display.
- Fixed multi-part Notation accessibility selection announcements and prevented harmony editing from clearing a selected stem note.
- Stabilized the Rest entry icon, matched Notation track controls, aligned stem Mute/Solo buttons, and limited MusicXML export to the selected Parts.
- Added full instrument names, abbreviations, and standard instrument sounds to exported MusicXML parts and Notation score labels.
- Added vertical workspace scrolling when expanded Notation tracks exceed the main window height.

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
