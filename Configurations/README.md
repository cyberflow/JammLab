# Build Configurations

This folder contains the first safe build-settings extraction for JammLab.

- `Base.xcconfig`: shared compiler and platform settings used by Debug and Release.
- `Debug.xcconfig`: local development settings with testability and no Swift optimization.
- `Release.xcconfig`: optimized release-style settings without changing signing or distribution.
- `CI.xcconfig`: CI-only signing override. It uses ad-hoc signing while preserving the active Xcode configuration's Debug or Release build settings.
- `Signing-Local.xcconfig.example`: local signing template without real secrets.

Do not commit `Signing-Local.xcconfig`, certificates, provisioning profiles, notarization credentials, or other signing secrets.
