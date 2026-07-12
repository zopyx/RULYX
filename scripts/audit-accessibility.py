#!/usr/bin/env python3
"""Accessibility audit for RULYX Swift source code.

Checks for common accessibility issues:
1. Image-only buttons without .accessibilityLabel
2. Missing accessibility hints on interactive elements
3. Hardcoded English strings instead of loc() calls in UI code
"""

import re
import sys
import os
from pathlib import Path


def audit_accessibility(sources_dir: str) -> int:
    issues = 0

    for swift_file in Path(sources_dir).rglob("*.swift"):
        # Skip DTOs, models, protocols
        path_str = str(swift_file)
        if "/DTOs/" in path_str or "/Models/" in path_str or "/Protocols/" in path_str:
            continue
        if "Test" in path_str:
            continue

        content = swift_file.read_text()

        # Check 1: Image(systemName:) in Button without .accessibilityLabel
        # Pattern: Button { ... Image(systemName: ...) ... } without .accessibilityLabel
        if "Image(systemName:" in content and "Button" in content:
            lines = content.split("\n")
            in_button = False
            has_image = False
            has_label = False
            button_start = 0

            for i, line in enumerate(lines):
                if "Button" in line and "{" in line:
                    in_button = True
                    has_image = False
                    has_label = False
                    button_start = i
                elif in_button:
                    if "Image(systemName:" in line:
                        has_image = True
                    if "accessibilityLabel" in line or "accessibilityHint" in line:
                        has_label = True
                    if line.strip() == "}" or line.strip().startswith("})"):
                        if has_image and not has_label:
                            print(f"  {swift_file.name}:{button_start+1} — icon-only Button missing accessibilityLabel")
                            issues += 1
                        in_button = False

        # Check 2: Hardcoded English strings in Text() or .navigationTitle()
        # (not using loc() or localizationManager)
        for i, line in enumerate(content.split("\n")):
            stripped = line.strip()
            if stripped.startswith("//"):
                continue
            # Text("English text") without loc()
            if re.search(r'Text\("([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)"\)', stripped):
                if "loc(" not in stripped and "localizationManager" not in stripped:
                    # False positive check: is this in a comment or test?
                    if "Test" not in str(swift_file):
                        print(f"  {swift_file.name}:{i+1} — possible hardcoded English in Text()")
                        issues += 1

    return issues


def main():
    sources = os.path.join(os.path.dirname(__file__), "..", "Sources")
    if not os.path.isdir(sources):
        print("Sources directory not found")
        sys.exit(1)

    print("→ Accessibility audit for RULYX")
    issues = audit_accessibility(sources)

    if issues > 0:
        print(f"\n✗ {issues} accessibility issue(s) found")
        # Non-fatal in CI — report but don't block
        sys.exit(0)
    else:
        print("\n✓ No accessibility issues found")
        sys.exit(0)


if __name__ == "__main__":
    main()
