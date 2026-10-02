#!/usr/bin/env python3
"""Print an `xcodebuild` destination for an available iPhone simulator.

CI runners and developer machines have different simulator sets, so a hard-coded UDID goes
stale (`xcodebuild: Unable to find a device …`) and a plain device *name* only resolves against
the newest runtime, which fails when that model does not exist for it. Preference order:

1. a device named like ``iPhone 17 (CI)`` — a dedicated automation device, when the repo has one,
2. the newest iOS runtime that offers an iPhone, preferring a shut-down device (a busy one can
   hang the run).

The result is passed to ``xcodebuild -destination``; override it per invocation
(``make test SIMULATOR_DESTINATION=…``) when a specific device is needed.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys

FALLBACK = "platform=iOS Simulator,name=iPhone 16 Pro Max"


def candidates() -> list[tuple[str, str, str, tuple[int, ...]]]:
    """(name, udid, state, runtime version) for every available iPhone simulator."""
    try:
        raw = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "available", "--json"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        devices = json.loads(raw)["devices"]
    except (subprocess.CalledProcessError, KeyError, json.JSONDecodeError):
        return []

    found = []
    for runtime, entries in devices.items():
        version = tuple(int(part) for part in re.findall(r"\d+", runtime.rsplit(".", 1)[-1]))
        for entry in entries:
            name = entry.get("name", "")
            if "iPhone" not in name or not entry.get("udid"):
                continue
            found.append((name, entry["udid"], entry.get("state", ""), version))
    return found


def rank(device: tuple[str, str, str, tuple[int, ...]]) -> tuple[bool, tuple[int, ...], bool]:
    name, _, state, version = device
    return ("(CI)" in name, version, state == "Shutdown")


def main() -> int:
    found = candidates()
    if not found:
        print(FALLBACK)
        return 0
    print(f"platform=iOS Simulator,id={max(found, key=rank)[1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
