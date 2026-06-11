# Third-Party Notices

This file lists third-party software that is used by or bundled with JammLab.
It is an engineering compliance inventory, not legal advice.

The bundled Python separator inventory was generated from the local
`build/JammLabSeparatorHelper/venv` package metadata used to build the
PyInstaller helper. Review this file whenever `JammLabSeparatorHelper`
dependencies, model files, or binary packaging change.

Apple system frameworks used by the native macOS app are not listed here.

## Release Review Notes

- The bundled separator includes `imageio-ffmpeg` and its FFmpeg binary
  `ffmpeg-macos-aarch64-v7.1`.
- The local FFmpeg binary reports `--enable-gpl` in its build configuration.
  FFmpeg documents that enabling GPL components changes the resulting FFmpeg
  binary's licensing obligations. Review this before distributing notarized
  public binary builds.
- The bundled separator model cache currently includes `htdemucs.yaml` and a
  `.th` model weights file. Review the upstream model/source license before
  distributing builds that include prefetched model weights.
- The bundled Python environment includes `diffq`, whose local package metadata
  reports `Creative Commons Attribution-NonCommercial 4.0 International`.
  Review whether this package is actually needed in the shipped helper and
  whether its terms are acceptable for the intended public release.

## Highlighted Bundled Projects

| Project | Version | License | Notes |
| --- | ---: | --- | --- |
| python-audio-separator / `audio-separator` | 0.44.2 | MIT | Bundled separator backend used by `JammLabSeparatorHelper`. |
| `imageio-ffmpeg` | 0.6.0 | BSD-2-Clause | Provides the bundled FFmpeg executable used by the Python helper. |
| FFmpeg | 7.1 | GPL review required for bundled binary | The bundled binary reports `--enable-gpl`. |
| diffq | 0.2.4 | CC BY-NC 4.0 metadata | Bundled transitive dependency; requires release review. |
| PyInstaller | 6.20.0 | GPLv2-or-later with PyInstaller exception | Used to package `JammLabSeparatorHelper`. |
| PyTorch / `torch` | 2.12.0 | BSD-3-Clause | Bundled ML runtime dependency. |
| ONNX Runtime / `onnxruntime` | 1.26.0 | MIT | Bundled inference runtime dependency. |
| NumPy | 2.4.6 | BSD-3-Clause and other permissive notices | Bundled numeric dependency. |
| SciPy | 1.17.1 | BSD-3-Clause, plus bundled native library notices | Bundled scientific dependency. |
| librosa | 0.11.0 | ISC | Bundled audio analysis dependency of separator stack. |
| SoundFile / `soundfile` | 0.13.1 | BSD-3-Clause | Bundled audio IO dependency. |
| pydub | 0.25.1 | MIT | Bundled audio utility dependency. |

## Bundled Python Package Inventory

| Package | Version | License metadata |
| --- | ---: | --- |
| `absl-py` | 2.4.0 | Apache-2.0 |
| `altgraph` | 0.17.5 | MIT |
| `audio-separator` | 0.44.2 | MIT |
| `audioop-lts` | 0.2.2 | PSF-2.0 |
| `audioread` | 3.1.0 | MIT |
| `beartype` | 0.18.5 | MIT |
| `certifi` | 2026.5.20 | MPL-2.0 |
| `cffi` | 2.0.0 | MIT |
| `charset-normalizer` | 3.4.7 | MIT |
| `Cython` | 3.2.5 | Apache-2.0 |
| `decorator` | 5.3.1 | BSD-2-Clause |
| `diffq` | 0.2.4 | Creative Commons Attribution-NonCommercial 4.0 International |
| `einops` | 0.8.2 | MIT |
| `filelock` | 3.29.0 | MIT |
| `flatbuffers` | 25.12.19 | Apache-2.0 |
| `fsspec` | 2026.4.0 | BSD-3-Clause |
| `idna` | 3.17 | BSD-3-Clause |
| `imageio-ffmpeg` | 0.6.0 | BSD-2-Clause |
| `Jinja2` | 3.1.6 | BSD |
| `joblib` | 1.5.3 | BSD-3-Clause |
| `julius` | 0.2.7 | MIT |
| `lazy-loader` | 0.5 | BSD-3-Clause |
| `librosa` | 0.11.0 | ISC |
| `llvmlite` | 0.47.0 | BSD-2-Clause and Apache-2.0 with LLVM exception |
| `macholib` | 1.16.4 | MIT |
| `MarkupSafe` | 3.0.3 | BSD-3-Clause |
| `ml_collections` | 1.1.0 | Apache-2.0 |
| `ml_dtypes` | 0.5.4 | Apache-2.0 |
| `mpmath` | 1.3.0 | BSD |
| `msgpack` | 1.1.2 | Apache-2.0 |
| `narwhals` | 2.22.0 | MIT |
| `networkx` | 3.6.1 | BSD-3-Clause |
| `numba` | 0.65.1 | BSD |
| `numpy` | 2.4.6 | BSD-3-Clause and other permissive notices |
| `onnx-weekly` | 1.22.0.dev20260519 | Apache-2.0 |
| `onnx2torch-py313` | 1.6.0 | Apache-2.0 |
| `onnxruntime` | 1.26.0 | MIT |
| `packaging` | 26.2 | Apache-2.0 or BSD-2-Clause |
| `pillow` | 12.2.0 | MIT-CMU |
| `pip` | 26.1.2 | MIT |
| `platformdirs` | 4.10.0 | MIT |
| `pooch` | 1.9.0 | BSD-3-Clause |
| `protobuf` | 7.35.0 | BSD-3-Clause |
| `pycparser` | 3.0 | BSD-3-Clause |
| `pydub` | 0.25.1 | MIT |
| `pyinstaller` | 6.20.0 | GPLv2-or-later with PyInstaller exception |
| `pyinstaller-hooks-contrib` | 2026.5 | Apache-2.0 and GPLv2 metadata |
| `PyYAML` | 6.0.3 | MIT |
| `requests` | 2.34.2 | Apache-2.0 |
| `resampy` | 0.4.3 | ISC |
| `rotary-embedding-torch` | 0.6.5 | MIT |
| `samplerate` | 0.1.0 | MIT |
| `scikit-learn` | 1.9.0 | BSD-3-Clause |
| `scipy` | 1.17.1 | BSD-3-Clause, with bundled native library notices in package metadata |
| `setuptools` | 81.0.0 | MIT |
| `six` | 1.17.0 | MIT |
| `soundfile` | 0.13.1 | BSD-3-Clause |
| `soxr` | 1.1.0 | LGPL-2.1-or-later |
| `standard-aifc` | 3.13.0 | PSF-2.0 |
| `standard-chunk` | 3.13.0 | PSF-2.0 |
| `standard-sunau` | 3.13.0 | PSF-2.0 |
| `sympy` | 1.14.0 | BSD |
| `threadpoolctl` | 3.6.0 | BSD-3-Clause |
| `torch` | 2.12.0 | BSD-3-Clause |
| `torchvision` | 0.27.0 | BSD |
| `tqdm` | 4.67.3 | MPL-2.0 and MIT |
| `typing_extensions` | 4.15.0 | PSF-2.0 |
| `urllib3` | 2.7.0 | MIT |
| `wheel` | 0.47.0 | MIT |

## Sources Checked

- Local Python package metadata from `build/JammLabSeparatorHelper/venv`.
- Local FFmpeg binary version output from `imageio-ffmpeg`.
- `JammLabSeparatorHelper/requirements.txt`.
- PyPI metadata for `audio-separator`.
- FFmpeg license documentation for `--enable-gpl` behavior.
