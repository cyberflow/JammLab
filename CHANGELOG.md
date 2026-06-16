# Changelog

All notable changes to JammLab will be documented in this file.

This project follows tag-based release versioning. Stable releases use tags in
the form `vMAJOR.MINOR.PATCH`, beta releases use `vMAJOR.MINOR.PATCH-beta`, and
development artifact builds use `vMAJOR.MINOR.PATCH-dev.N`.

## Unreleased

- Add tempo/time signature markers that update the timeline beat grid and metronome from their marker position.
- Add a stem separation method picker with a two-stem vocals/instrumental option.
- Limit microphone permission requests to the tuner and honor the selected audio input device.
- Improve pitch analysis performance by reducing per-window allocation during track analysis.
- Add a live chromatic tuner window that uses the selected audio input device, keeps its UI minimal, and supports low bass notes down to A0.
- Open the sidecar video window automatically for imported videos and persist its open state in saved video projects.
- Add unsigned DMG packaging for release tags.
- Support stable, beta, and development tag builds in GitHub CI.

## 0.1.0

- Initial public release placeholder.
