# -*- mode: python ; coding: utf-8 -*-

from PyInstaller.utils.hooks import collect_all, collect_submodules, copy_metadata
from pathlib import Path


block_cipher = None

datas = []
binaries = []
hiddenimports = []

for package in [
    "audio_separator",
    "imageio_ffmpeg",
    "librosa",
    "numpy",
    "onnxruntime",
    "pydub",
    "scipy",
    "soundfile",
    "torch",
    "tqdm",
]:
    package_datas, package_binaries, package_hiddenimports = collect_all(package)
    datas += package_datas
    binaries += package_binaries
    hiddenimports += package_hiddenimports
    hiddenimports += collect_submodules(package)

for distribution in [
    "audio-separator",
    "imageio-ffmpeg",
    "numpy",
    "onnxruntime",
    "torch",
]:
    try:
        datas += copy_metadata(distribution)
    except Exception:
        pass

model_cache_dir = Path("..") / "build" / "JammLabSeparatorHelper" / "model-cache"
if model_cache_dir.is_dir():
    datas += [(str(model_cache_dir), "bundled-model-cache")]

a = Analysis(
    ["runner.py"],
    pathex=[],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["tensorflow"],
    noarchive=True,
    optimize=0,
)
pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="JammLabSeparatorHelper",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="JammLabSeparatorHelper",
)
