#!/usr/bin/env python3
"""Select expensive packaging checks while keeping ordinary CI checks visible."""

import json
import os
import subprocess
from pathlib import Path


def affects_helper(path):
    return (path.startswith(("JammLabSeparatorHelper/", "JammLabStemHelper/", ".github/workflows/", "Configurations/"))
            or path in {"scripts/package_dmg.sh", "scripts/derive_release_metadata.sh",
                        "JammLab.xcodeproj/project.pbxproj", "JammLab/JammLab.entitlements",
                        "JammLab/JammLab.Release.entitlements"}
            or (path.startswith("scripts/") and "separator" in path))


def needs_full_check(event_name, ref, paths):
    return event_name == "workflow_dispatch" or ref.startswith("refs/tags/v") or any(map(affects_helper, paths))


def changed_paths(event_name, event):
    if event_name == "pull_request":
        base, head = event["pull_request"]["base"]["sha"], event["pull_request"]["head"]["sha"]
        revision = f"{base}...{head}"
    else:
        base, head = event.get("before", ""), event.get("after", "HEAD")
        if not base or set(base) == {"0"}:
            # A new branch has no before commit: conservatively validate packaging.
            return [".github/workflows/ci.yml"]
        revision = f"{base}..{head}"
    result = subprocess.run(["git", "diff", "--no-renames", "--name-only", "-z", revision], check=True, capture_output=True)
    return result.stdout.decode().rstrip("\0").split("\0")


def main():
    event_name, ref = os.environ["GITHUB_EVENT_NAME"], os.environ["GITHUB_REF"]
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    paths = [] if event_name == "workflow_dispatch" or ref.startswith("refs/tags/v") else changed_paths(event_name, event)
    required = needs_full_check(event_name, ref, paths)
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"helper_required={str(required).lower()}\n")
    print(f"Full helper validation: {required}")


if __name__ == "__main__":
    main()
