#!/usr/bin/env python3
"""Repair placeholder mismatches by falling back to the English source string."""

from __future__ import annotations

import json
import os
import re

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCALIZATIONS_DIR = os.path.join(PROJECT_ROOT, "Sources", "Shared", "Localizations")

SUPPORTED_LANGUAGES = [
    "de",
    "fr",
    "it",
    "ja",
    "zh",
    "es",
    "pt",
    "ko",
    "ru",
    "ar",
    "nl",
    "pl",
    "tr",
    "th",
    "vi",
]

PLACEHOLDER_RE = re.compile(r"\{[A-Za-z0-9_]+\}")


def placeholders(value: str) -> set[str]:
    return set(PLACEHOLDER_RE.findall(value))


def main() -> None:
    with open(os.path.join(LOCALIZATIONS_DIR, "en.json"), encoding="utf-8") as handle:
        english = json.load(handle)

    repairs = 0
    for language in SUPPORTED_LANGUAGES:
        path = os.path.join(LOCALIZATIONS_DIR, f"{language}.json")
        with open(path, encoding="utf-8") as handle:
            localized = json.load(handle)

        changed = False
        for key, english_value in english.items():
            localized_value = localized.get(key, "")
            if placeholders(english_value) != placeholders(localized_value):
                localized[key] = english_value
                changed = True
                repairs += 1

        if changed:
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(localized, handle, indent=2, ensure_ascii=False)
                handle.write("\n")

    print(f"Repaired {repairs} placeholder mismatch entries.")


if __name__ == "__main__":
    main()
