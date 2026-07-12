#!/usr/bin/env python3
"""Check Xcode code coverage against a minimum threshold."""

import json
import sys
import subprocess
import glob
import os


def find_latest_xcresult():
    """Find the most recent .xcresult in DerivedData."""
    derived = os.path.expanduser("~/Library/Developer/Xcode/DerivedData")
    pattern = os.path.join(derived, "RULYX-*", "Logs", "Test", "*.xcresult")
    results = sorted(glob.glob(pattern), key=os.path.getmtime, reverse=True)
    return results[0] if results else None


def main():
    threshold = float(sys.argv[1]) if len(sys.argv) > 1 else 50.0

    xcresult = find_latest_xcresult()
    if not xcresult:
        print("::warning::No .xcresult found, skipping coverage check")
        sys.exit(0)

    result = subprocess.run(
        ["xcrun", "xccov", "view", "--report", xcresult, "--json"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"::warning::xccov failed: {result.stderr}")
        sys.exit(0)

    data = json.loads(result.stdout)
    targets = [t for t in data.get("targets", []) if t.get("name") == "RULYX"]
    if not targets:
        print("::warning::RULYX target not found in coverage data")
        sys.exit(0)

    line_coverage = targets[0].get("lineCoverage", 0) * 100
    print(f"Line coverage: {line_coverage:.1f}% (threshold: {threshold:.0f}%)")

    if line_coverage < threshold:
        print(f"::error::Coverage {line_coverage:.1f}% is below {threshold:.0f}% threshold")
        sys.exit(1)

    print(f"::notice::Coverage check passed ({line_coverage:.1f}% >= {threshold:.0f}%)")


if __name__ == "__main__":
    main()
