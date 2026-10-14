#!/usr/bin/env python3
"""Exercise the packaged helper, including its seeded cache, without network access."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_STEMS = {
    "htdemucs.yaml": {"vocals", "drums", "bass", "other"},
    "htdemucs_6s.yaml": {"vocals", "drums", "bass", "other", "guitar", "piano"},
    "UVR-MDX-NET-Inst_HQ_5.onnx": {"vocals", "instrumental"},
}
SANDBOX = '(version 1) (allow default) (deny network*)'


def validate_outputs(directory, expected, duration=10.0):
    files = sorted(directory.glob("*.wav"))
    if len(files) != len(expected):
        raise ValueError(f"Expected {len(expected)} WAV stems, found {len(files)} in {directory}")
    for stem in expected:
        if not any(f"({stem})" in path.stem.lower() for path in files):
            raise ValueError(f"Missing stem {stem}: {[path.name for path in files]}")
    for path in files:
        audio, rate = sf.read(path, always_2d=True)
        if not len(audio) or not np.isfinite(audio).all():
            raise ValueError(f"Empty or non-finite audio: {path}")
        if abs(len(audio) / rate - duration) > 0.1:
            raise ValueError(f"Wrong stem duration: {path}: {len(audio) / rate}")
    return [path.name for path in files]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("helper", type=Path)
    parser.add_argument("--report-dir", required=True, type=Path)
    args = parser.parse_args()
    helper = args.helper.resolve(strict=True)
    report = args.report_dir.resolve()
    report.mkdir(parents=True, exist_ok=True)
    manifest_path = ROOT / "JammLabSeparatorHelper/helper-manifest.json"
    manifest = json.loads(manifest_path.read_text())
    if set(EXPECTED_STEMS) != {model["name"] for model in manifest["models"]}:
        raise ValueError("Update smoke-test expectations for the changed model manifest")

    results = []
    with tempfile.TemporaryDirectory(prefix="jammlab-offline-smoke-") as temporary:
        work = Path(temporary)
        # HOME is set only in the child environment, never repurposed in the shell.
        for name in ("home", "tmp", "empty-path"):
            (work / name).mkdir()
        env = {"HOME": str(work / "home"), "TMPDIR": str(work / "tmp"),
               "PATH": str(work / "empty-path"), "PYTHONNOUSERSITE": "1",
               "LANG": "en_US.UTF-8", "OMP_NUM_THREADS": "2"}

        def run(arguments, name, timeout=1800):
            command = ["/usr/bin/sandbox-exec", "-p", SANDBOX, *map(str, arguments)]
            start = time.monotonic()
            with (report / f"{name}.log").open("w") as log:
                subprocess.run(command, env=env, cwd=work, stdout=log, stderr=subprocess.STDOUT,
                               check=True, timeout=timeout)
            return time.monotonic() - start

        # Fail closed if the host cannot enforce the network restriction.
        run([sys.executable, "-c", "import errno,socket; s=socket.socket(); "
             "assert s.connect_ex(('127.0.0.1',9)) in (errno.EPERM,errno.EACCES)"], "network-denial", 30)
        run([helper, "--capabilities_json"], "capabilities", 60)
        capabilities = json.loads((report / "capabilities.log").read_text())
        for field in ("protocolVersion", "separatorVersion", "supportedComputeModes"):
            if capabilities[field] != manifest[field]:
                raise ValueError(f"Incorrect helper capability: {field}")
        if capabilities["manifestSHA256"] != hashlib.sha256(manifest_path.read_bytes()).hexdigest():
            raise ValueError("Packaged helper manifest does not match the source manifest")
        if set(capabilities["supportedModels"]) != set(EXPECTED_STEMS):
            raise ValueError("Packaged helper does not support the expected models")
        run([helper, "--env_info"], "environment", 120)
        environment = (report / "environment.log").read_text()
        if any(word in environment for word in ("not-installed", "not-bundled", "unavailable:")):
            raise ValueError("Packaged helper reports missing runtime dependencies")

        rate = 44100
        t = np.arange(10 * rate) / rate
        envelope = 0.5 + 0.5 * np.sin(2 * np.pi * 2 * t)
        signal = envelope * sum(0.1 * np.sin(2 * np.pi * frequency * t) for frequency in (110, 220, 440))
        source = work / "fixture.wav"
        sf.write(source, np.column_stack((signal, signal * 0.8)), rate, subtype="PCM_16")
        for index, model in enumerate(manifest["models"]):
            name = model["name"]
            output = work / f"output-{index}"
            cache = work / f"empty-model-cache-{index}"
            elapsed = run([helper, source, "--output_dir", output, "--model_file_dir", cache,
                           "--model_filename", name, "--output_format", "WAV", "--compute_device", "cpu"],
                          f"model-{index}")
            run([helper, "--validate_model_cache", name, "--model_file_dir", cache], f"cache-{index}", 60)
            files = validate_outputs(output, EXPECTED_STEMS[name])
            results.append({"model": name, "seconds": elapsed, "stems": files})
            (report / "results.json").write_text(json.dumps(results, indent=2) + "\n")
            print(f"PASS {name}: {elapsed:.1f}s, {len(files)} stems", flush=True)


if __name__ == "__main__":
    main()
