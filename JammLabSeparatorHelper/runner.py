#!/usr/bin/env python3
"""Bundled audio-separator wrapper for JammLab.

This executable intentionally mirrors the subset of the audio-separator CLI
used by the Swift stem helper. Keeping this thin wrapper stable lets the Swift
job watcher remain responsible for IPC, heartbeat, cancellation, and cache
normalization while the Python runtime is bundled inside the app.
"""

from __future__ import annotations

import argparse
import importlib.metadata
import logging
import os
import platform
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


HELPER_VERSION = "1"
BUNDLED_MODEL_CACHE_DIR_NAME = "bundled-model-cache"
RUNTIME_DIR_NAME = "JammLabSeparatorHelper"
DEFAULT_COMPUTE_DEVICE = "cpu"


def _package_version(name: str) -> str:
    try:
        return importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        return "not-installed"


def bundled_resource_root() -> Path:
    if hasattr(sys, "_MEIPASS"):
        return Path(sys._MEIPASS)
    return Path(__file__).resolve().parent


def bundled_model_cache_dir() -> Path:
    return bundled_resource_root() / BUNDLED_MODEL_CACHE_DIR_NAME


def bundled_ffmpeg_path() -> Path | None:
    try:
        import imageio_ffmpeg
    except Exception:
        return None

    try:
        return Path(imageio_ffmpeg.get_ffmpeg_exe()).resolve()
    except Exception:
        return None


def configure_bundled_ffmpeg() -> Path | None:
    ffmpeg_path = bundled_ffmpeg_path()
    if ffmpeg_path is None:
        return None

    shim_dir = Path(tempfile.gettempdir()) / RUNTIME_DIR_NAME / "bin"
    shim_dir.mkdir(parents=True, exist_ok=True)
    shim_path = shim_dir / "ffmpeg"

    if shim_path.exists() or shim_path.is_symlink():
        try:
            if shim_path.resolve() != ffmpeg_path:
                shim_path.unlink()
        except OSError:
            shim_path.unlink(missing_ok=True)

    if not shim_path.exists():
        try:
            shim_path.symlink_to(ffmpeg_path)
        except OSError:
            shutil.copy2(ffmpeg_path, shim_path)
            shim_path.chmod(0o755)

    os.environ["PATH"] = f"{shim_dir}{os.pathsep}{os.environ.get('PATH', '')}"
    return shim_path


def configure_runtime_cache_dirs() -> None:
    cache_root = Path(tempfile.gettempdir()) / RUNTIME_DIR_NAME / "cache"
    cache_root.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault("NUMBA_CACHE_DIR", str(cache_root / "numba"))
    os.environ.setdefault("LIBROSA_CACHE_DIR", str(cache_root / "librosa"))


def configure_compute_device(compute_device: str) -> None:
    normalized = compute_device.strip().lower()
    if normalized == "auto":
        return
    if normalized != "cpu":
        raise SystemExit(f"Unsupported --compute_device: {compute_device}")

    # audio-separator auto-selects Apple MPS/CoreML when available. That path
    # currently trips a Metal shader assertion on macOS 26, so the bundled
    # helper defaults to a stable CPU backend.
    os.environ.setdefault("ORT_DISABLE_ALL", "1")
    try:
        import torch
    except Exception:
        return

    if hasattr(torch.backends, "mps"):
        torch.backends.mps.is_available = lambda: False


def copy_seed_model_cache(model_dir: Path, seed_dir: Path | None = None) -> int:
    source_dir = seed_dir if seed_dir is not None else bundled_model_cache_dir()
    if not source_dir.is_dir():
        return 0

    copied = 0
    model_dir.mkdir(parents=True, exist_ok=True)
    for source_path in source_dir.rglob("*"):
        if not source_path.is_file():
            continue

        relative_path = source_path.relative_to(source_dir)
        destination_path = model_dir / relative_path
        if destination_path.exists():
            continue

        destination_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_path, destination_path)
        copied += 1

    return copied


def ffmpeg_version(ffmpeg_path: Path | None) -> str:
    if ffmpeg_path is None:
        return "not-bundled"

    try:
        output = subprocess.check_output([str(ffmpeg_path), "-version"], text=True, stderr=subprocess.STDOUT)
        return output.splitlines()[0]
    except Exception as error:
        return f"unavailable: {error}"


def print_env_info() -> int:
    packages = [
        "audio-separator",
        "numpy",
        "onnxruntime",
        "torch",
    ]
    configure_runtime_cache_dirs()
    ffmpeg_path = configure_bundled_ffmpeg()
    model_cache_dir = bundled_model_cache_dir()
    print(f"JammLabSeparatorHelper/{HELPER_VERSION}")
    print(f"python: {platform.python_version()}")
    print(f"platform: {platform.platform()}")
    print(f"ffmpeg: {ffmpeg_version(ffmpeg_path)}")
    print(f"bundledModelCache: {model_cache_dir if model_cache_dir.is_dir() else 'not-bundled'}")
    for package in packages:
        print(f"{package}: {_package_version(package)}")
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="JammLabSeparatorHelper",
        description="Bundled JammLab stem separator backend.",
    )
    parser.add_argument("--env_info", action="store_true", help="Print bundled backend diagnostics and exit.")
    parser.add_argument("--prefetch_model", help="Download/cache a model into --model_file_dir and exit.")
    parser.add_argument("audio_path", nargs="?", help="Audio file to separate.")
    parser.add_argument("-m", "--model_filename", "--model_name", dest="model_filename", default="htdemucs.yaml")
    parser.add_argument("--output_format", default="WAV")
    parser.add_argument("--output_dir", required=False)
    parser.add_argument("--model_file_dir", required=False)
    parser.add_argument("--log_level", default="INFO")
    parser.add_argument(
        "--compute_device",
        default=DEFAULT_COMPUTE_DEVICE,
        help="Compute backend to use: cpu or auto. Defaults to cpu for stable bundled macOS separation.",
    )
    return parser.parse_args(argv)


def parse_log_level(value: str) -> int:
    normalized = value.strip()
    if normalized.isdigit():
        return int(normalized)

    level = logging.getLevelName(normalized.upper())
    if isinstance(level, int):
        return level

    raise SystemExit(f"Unsupported --log_level: {value}")


def separate(args: argparse.Namespace) -> int:
    if not args.audio_path:
        raise SystemExit("audio_path is required unless --env_info is used")
    if not args.output_dir:
        raise SystemExit("--output_dir is required")
    if not args.model_file_dir:
        raise SystemExit("--model_file_dir is required")

    output_dir = Path(args.output_dir)
    model_dir = Path(args.model_file_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    model_dir.mkdir(parents=True, exist_ok=True)
    configure_runtime_cache_dirs()
    configure_bundled_ffmpeg()
    configure_compute_device(args.compute_device)
    copy_seed_model_cache(model_dir)

    # Import lazily so --env_info stays fast and can report missing packages.
    from audio_separator.separator import Separator

    separator = Separator(
        output_dir=str(output_dir),
        output_format=args.output_format,
        model_file_dir=str(model_dir),
        log_level=parse_log_level(args.log_level),
    )
    separator.load_model(model_filename=args.model_filename)
    output_files = separator.separate(args.audio_path)
    if not output_files:
        raise SystemExit("Separation produced no output files")

    for output_file in output_files:
        print(output_file)
    return 0


def prefetch_model(args: argparse.Namespace) -> int:
    if not args.model_file_dir:
        raise SystemExit("--model_file_dir is required")

    model_dir = Path(args.model_file_dir)
    model_dir.mkdir(parents=True, exist_ok=True)
    configure_runtime_cache_dirs()
    configure_bundled_ffmpeg()
    configure_compute_device(args.compute_device)

    from audio_separator.separator import Separator

    with tempfile.TemporaryDirectory(prefix="jammlab-separator-prefetch-") as output_dir:
        separator = Separator(
            output_dir=output_dir,
            output_format=args.output_format,
            model_file_dir=str(model_dir),
            log_level=parse_log_level(args.log_level),
        )
        separator.load_model(model_filename=args.prefetch_model)

    print(f"Prefetched {args.prefetch_model} into {model_dir}")
    return 0


def main(argv: list[str] | None = None) -> int:
    os.environ.setdefault("PYTHONNOUSERSITE", "1")
    args = parse_args(list(sys.argv[1:] if argv is None else argv))
    if args.env_info:
        return print_env_info()
    if args.prefetch_model:
        return prefetch_model(args)
    return separate(args)


if __name__ == "__main__":
    raise SystemExit(main())
