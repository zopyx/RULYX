#!/usr/bin/env python3
"""Sync JSON localization bundles into Localizable.xcstrings."""

from __future__ import annotations

import json
import os
from collections import OrderedDict

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCALIZATIONS_DIR = os.path.join(PROJECT_ROOT, "Sources", "Shared", "Localizations")
XCSTRINGS_PATH = os.path.join(LOCALIZATIONS_DIR, "Localizable.xcstrings")

SUPPORTED_LANGUAGES = [
    "en",
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


def load_json_bundles() -> dict[str, dict[str, str]]:
    bundles: dict[str, dict[str, str]] = {}
    for lang in SUPPORTED_LANGUAGES:
        path = os.path.join(LOCALIZATIONS_DIR, f"{lang}.json")
        with open(path, encoding="utf-8") as handle:
            bundles[lang] = json.load(handle)
    return bundles


def load_xcstrings() -> dict:
    with open(XCSTRINGS_PATH, encoding="utf-8") as handle:
        return json.load(handle)


def localization_entry(value: str) -> dict:
    return {
        "stringUnit": {
            "state": "translated",
            "value": value,
        }
    }


def sync() -> None:
    bundles = load_json_bundles()
    xcstrings = load_xcstrings()
    strings = xcstrings.setdefault("strings", {})

    for key in sorted(bundles["en"].keys()):
        entry = strings.get(key, {})
        entry["extractionState"] = "manual"
        localizations = entry.get("localizations", {})
        for lang in SUPPORTED_LANGUAGES:
            localizations[lang] = localization_entry(bundles[lang][key])
        entry["localizations"] = OrderedDict((lang, localizations[lang]) for lang in SUPPORTED_LANGUAGES)
        strings[key] = entry

    xcstrings["strings"] = OrderedDict((key, strings[key]) for key in sorted(strings.keys()))

    with open(XCSTRINGS_PATH, "w", encoding="utf-8") as handle:
        json.dump(xcstrings, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


if __name__ == "__main__":
    sync()
