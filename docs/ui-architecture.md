# JammLab UI Architecture

## Current UI Shape

JammLab is a native macOS SwiftUI app. The main workspace is composed by `ContentView`, while detailed panels live in `Views/MainWorkspacePanels.swift`. Timeline rendering remains split across `WaveformTimelineView`, `TimelineTracks`, `PeakformTimelineView`, and interaction helpers.

The UI refactor keeps existing behavior intact and introduces a small design-system layer so future visual work can change colors, spacing, radii, and control sizes from one place.

## Design Tokens

Use `DesignSystem/AppTheme.swift` for shared visual values and inject runtime palette colors through `Environment(\.appColors)`:

- `AppTheme.Colors`: non-user-editable semantic colors such as timeline warning/playhead colors.
- `AppThemeColors`: user-editable app chrome, text, control, accent, status button, value slider, waveform, and timeline colors.
- `AppTheme.Spacing`: common spacing and padding scale.
- `AppTheme.Radius`: shared corner radii.
- `AppTheme.Typography`: common SwiftUI font choices.
- `AppTheme.ControlSize`: reusable control widths and fixed layout sizes.
- `AppTheme.Timeline`: timeline track heights, marker sizes, line widths, opacities, and waveform drawing values.
- `AppTheme.Window`: app and help-window dimensions.

Do not add new hardcoded colors, spacing, radii, or timeline dimensions in views unless the value is local to a one-off drawing calculation. If a value affects app style or repeated layout, add it to `AppTheme`.

## Reusable Components

Reusable UI components live in `Views/Components/`:

- `AppPanel`: standard card/panel surface.
- `AppSectionTitle`: shared section heading.
- `AppControlButton`: active/inactive bordered control buttons.
- `AbletonNumberField`: compact DAW-style numeric input with click-to-select, drag-to-adjust, keyboard replacement input, and double-click default reset.
- `JammValueSlider`: compact DAW-style value slider with normalized fill, value text inside the control, drag-to-adjust behavior, and double-click default reset.
- `NoteRowView`: shared Notes/Regions list row.

When adding new controls, prefer composing these components before adding a new local helper inside a screen. App value sliders should use `JammValueSlider` unless a task explicitly needs a native macOS slider. Numeric tempo/value fields use `AbletonNumberField`. New `AbletonNumberField` and `JammValueSlider` instances must explicitly define `defaultValue`, `minValue`, `maxValue`, `step`, `precision`, and `accessibilityLabel`.

## Main Workspace

`ContentView` owns the high-level shell, global toolbar, edit-note alert, keyboard focus handling, drag/drop import routing, and app-level hotkey dispatch. It should stay thin.

Audio/video import remains an audio-first flow. `AudioFileImporter` accepts local MP3/WAV audio and MP4/MOV/M4V video; video audio is extracted to a temporary app media cache while a project is unsaved, then saved projects keep the extracted `audio.m4a` in the project-local `media/` directory. The extracted audio is rendered through the same waveform/playback/stem pipeline as normal audio. The video surface is a separate muted sidecar window managed outside the timeline, so timeline layout and audio transport stay the source of truth.

`Views/MainWorkspacePanels.swift` owns the visual composition of:

- the loaded workspace layout;
- the timeline workspace section;
- the right inspector wiring;
- the bottom transport bar wiring.

Keep business rules and persistence out of these views. Panels should call `AudioPlayerViewModel` through existing methods and bindings.

The main screen is organized as:

- global toolbar: `TopToolbarView`;
- timeline/waveform area: `WaveformTimelineView`;
- no-file import prompt: waveform placeholder inside `PeakformTimelineView`; keep the main workspace visible and disabled rather than replacing it with a separate empty-state screen;
- stems/mixer lanes: `StemTracksSection` inside `WaveformTimelineView`, sharing the timeline viewport;
- right sidebar: `InspectorSidebarView`;
- bottom transport panel: `TransportBarView` and `TransportControlsView`.

The transport bar is a sibling of the timeline section, not a timeline track. Keep playback controls in `TransportBarView`/`TransportControlsView` so future timeline lanes such as stems, chord markers, or automation tracks can be added without changing transport layout.

`TopToolbarView` should stay grouped by purpose: project settings, practice/editing tools, and processing actions. Do not add unrelated controls to the top-level toolbar `HStack` without putting them in a semantic group.

## Timeline Styling

Timeline layers must share one visual and coordinate system:

- dimensions and opacities come from `AppTheme.Timeline`;
- visible time range comes from `TimelineViewport`;
- rendering layers must not own project state;
- interactions should continue to emit callbacks to the ViewModel.
- transport controls must stay outside timeline track views.

Future zoom, snap, region, marker, or beat-grid visual work should update tokens/components first where possible.

## Peakform Rendering

Waveform peakforms use a multi-resolution cache generated by `CachedPeakformProvider`. The provider decodes audio once, builds all configured LOD levels, and stores one v2 `.peakform` file in `Application Support/JammLab/PeakformCache` for unsaved projects and legacy fallback. Once a project is saved, project-specific peakforms are persisted in the project-local `peaks/` directory through `ProjectArtifactStore`.

`PeakformRenderer` chooses the best level for the current `TimelineViewport` and timeline width. Renderers should use only the visible peak range and aggregate by screen columns when there are more peaks than horizontal pixels. The cache layer must stay independent of SwiftUI and must not read or write legacy `.peakform` files next to the source audio.

## Project Artifacts

Saved projects keep project-specific generated artifacts next to the `.jammlab` file. In the default Save As flow, `Create subdirectory for project` creates/selects a project folder, writes `<ProjectName>.jammlab` inside it, and opens sandbox security-scoped access on that folder so artifacts can be written reliably. Saving a bare `.jammlab` file with the checkbox off is an advanced/non-sandbox-friendly path and can only write artifacts next to the file when the app already has access to the parent folder.

- `stems/`: separated stem WAV files plus `metadata.json`;
- `peaks/`: main and stem peakform binaries;
- `media/`: extracted video audio, currently `audio.m4a`.

For unsaved projects, Application Support remains a staging cache. On first successful Save/Save As, available project artifacts are copied into the project folder and only then are the corresponding temporary app-cache entries removed. `StemModels` remains a shared backend dependency cache in Application Support and is not a project artifact.

## Stem Backend UI

Stem separation uses bundled helpers, not a user-selected external executable. `SettingsView` may show the active backend and cache behavior, but it should not ask users to configure an `audio-separator` path. Runtime separation goes through `JammLabStemHelper` plus the bundled `JammLabSeparatorHelper` payload in app resources. The payload includes the Python runtime, ffmpeg provider, and prefilled model cache; at runtime the cache is seeded into `Application Support/JammLab/StemModels`.

## UI Change Rules

- Keep visual refactors separate from audio/playback changes.
- Do not change ViewModel public API for styling-only work unless there is no reasonable alternative.
- Avoid local hardcoded `Color(...)`, `.padding(16)`, `cornerRadius: 8`, fixed timeline heights, or repeated font definitions.
- Prefer semantic token names over raw values.
- Add reusable layout dimensions to `AppTheme.ControlSize`, semantic colors to `AppTheme.Colors`, and repeated transport/timeline values to their dedicated token groups.
- Keep macOS system semantics where useful: window background, control background, primary/secondary text.
- Add comments only when a visual rule is non-obvious or protects interaction behavior.

## Manual QA Checklist

After UI or project-flow refactors, verify:

- waveform import prompt and drag/drop import;
- audio and video import, including optional Video Window behavior;
- File menu open/save/save-as/recent/new project;
- project folder save/open with local `stems/`, `peaks/`, and `media/` artifacts;
- playback play/pause/stop and space hotkey;
- speed, pitch, current time, and waveform alignment;
- beat grid controls, time signature, click toggle, click volume, snap, and nudge buttons;
- timeline zoom/scroll, seek, snap, loop handles, region edit handles;
- stem separation, Stems/Original mode switch, stem mute/solo, and stem volume;
- Settings sections for theme colors, click, stem backend, and audio devices;
- Notes/Regions list selection, edit, color, delete, and context menus;
- sandbox-sensitive flows: import from `~/Music`, Save As project folder, reopen moved project folder;
- Help > Keyboard Shortcuts.

## Remaining UI Debt

- `MainWorkspacePanels.swift` still has many app-specific controls in one file; split by feature when visual work grows.
- `WaveformTimelineView.swift` still owns a large callback surface; group state/actions in a future pass.
- Menus in `JammLabApp.swift` are functional but not abstracted into menu sections.
- Timeline drawing still mixes rendering math and style calls, though tokenized values now live in `AppTheme`.
- Future iOS support will need platform-specific tokens for window/panel colors and menu behavior.
