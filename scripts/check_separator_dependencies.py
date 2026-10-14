#!/usr/bin/env python3
"""Validate the helper's version lock without importing its ML dependencies."""

import argparse
import hashlib
import importlib.metadata
import platform
import re
from pathlib import Path

HELPER = Path(__file__).resolve().parents[1] / "JammLabSeparatorHelper"
LOCK_NAME = "requirements-macos-arm64.lock"
INPUTS = (".python-version", "requirements.txt", "requirements-build.txt", "build-constraints.txt")
DIGEST_PREFIX = "# inputs-sha256: "


def canonical_name(name):
    return re.sub(r"[-_.]+", "-", name).lower()


def read_pins(path):
    pins = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line == "-r requirements.txt":
            continue
        match = re.fullmatch(r"([\w.-]+)(?:\[[\w,.-]+\])?==([\w.+!-]+)", line)
        if not match:
            raise ValueError(f"{path.name}: expected an exact package==version pin: {line}")
        name, version = canonical_name(match[1]), match[2]
        if name in pins:
            raise ValueError(f"{path.name}: duplicate package: {name}")
        pins[name] = version
    return pins


def input_digest(helper):
    digest = hashlib.sha256()
    for name in INPUTS:
        digest.update(name.encode() + b"\0" + (helper / name).read_bytes() + b"\0")
    return digest.hexdigest()


def validate_lock(helper):
    lock = helper / LOCK_NAME
    expected_header = DIGEST_PREFIX + input_digest(helper)
    if expected_header not in lock.read_text().splitlines():
        raise ValueError("Dependency inputs changed. Regenerate and validate the helper lock (CONTRIBUTING.md).")
    pins = read_pins(lock)
    for name in INPUTS[1:]:
        for package, version in read_pins(helper / name).items():
            if pins.get(package) != version:
                raise ValueError(f"{name}: {package}=={version} disagrees with {LOCK_NAME}")
    for package in ("pip", "setuptools", "wheel", "pyinstaller-hooks-contrib"):
        if package not in pins:
            raise ValueError(f"Missing build dependency: {package}")
    return pins


def validate_platform(helper, system=None, machine=None, version=None):
    actual = (system or platform.system(), machine or platform.machine(), version or platform.python_version())
    expected = ("Darwin", "arm64", (helper / ".python-version").read_text().strip())
    if actual != expected:
        raise ValueError(f"Helper build requires {expected}; found {actual}. Set PYTHON_BIN to the pinned arm64 Python.")


def validate_environment(pins, installed=None):
    if installed is None:
        installed = {canonical_name(d.metadata["Name"]): d.version for d in importlib.metadata.distributions()}
    differences = [f"{name}: expected {pins.get(name, 'absent')}, found {installed.get(name, 'absent')}"
                   for name in sorted(pins.keys() | installed.keys()) if pins.get(name) != installed.get(name)]
    if differences:
        raise ValueError("Environment does not match lock:\n" + "\n".join(differences))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-platform", action="store_true")
    parser.add_argument("--check-environment", action="store_true")
    parser.add_argument("--refresh-input-digest", action="store_true", help="Only when intentionally regenerating the lock")
    args = parser.parse_args()
    if args.refresh_input_digest:
        lock = HELPER / LOCK_NAME
        lines = [line for line in lock.read_text().splitlines() if not line.startswith(DIGEST_PREFIX)]
        lock.write_text(DIGEST_PREFIX + input_digest(HELPER) + "\n" + "\n".join(lines) + "\n")
    try:
        pins = validate_lock(HELPER)
        if args.check_platform:
            validate_platform(HELPER)
        if args.check_environment:
            validate_environment(pins)
    except ValueError as error:
        parser.exit(1, f"error: {error}\n")
    print(f"Validated {len(pins)} pinned helper dependencies")


if __name__ == "__main__":
    main()
