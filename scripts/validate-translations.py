#!/usr/bin/env python3
"""Validate translation files, placeholder parity, and xcstrings sync."""

import json
import os
import re
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCALIZATIONS_DIR = os.path.join(PROJECT_ROOT, "Sources", "Shared", "Localizations")
XCSTRINGS_PATH = os.path.join(LOCALIZATIONS_DIR, "Localizable.xcstrings")

SUPPORTED_LANGUAGES = [
    "en", "de", "fr", "it", "ja", "zh", "es", "pt",
    "ko", "ru", "ar", "nl", "pl", "tr", "th", "vi",
]

PLACEHOLDER_RE = re.compile(r"\{[A-Za-z0-9_]+\}")


def placeholders(value: str) -> set[str]:
    return set(PLACEHOLDER_RE.findall(value))


def main():
    en_path = os.path.join(LOCALIZATIONS_DIR, "en.json")
    if not os.path.exists(en_path):
        print(f"FAIL: en.json not found at {en_path}")
        sys.exit(1)

    with open(en_path) as f:
        en = json.load(f)

    with open(XCSTRINGS_PATH) as f:
        xcstrings = json.load(f).get("strings", {})

    bundles = {"en": en}
    for lang in SUPPORTED_LANGUAGES:
        if lang == "en":
            continue
        path = os.path.join(LOCALIZATIONS_DIR, f"{lang}.json")
        if not os.path.exists(path):
            continue
        with open(path) as f:
            bundles[lang] = json.load(f)

    issues = []

    empty = [k for k, v in en.items() if not v.strip()]
    if empty:
        issues.append(f"en.json: {len(empty)} empty value(s): {empty}")

    ph = [k for k, v in en.items() if k == v.strip()]
    if ph:
        issues.append(f"en.json: {len(ph)} key(s) where value equals key: {ph}")

    for lang in SUPPORTED_LANGUAGES:
        if lang == "en":
            continue
        path = os.path.join(LOCALIZATIONS_DIR, f"{lang}.json")
        if not os.path.exists(path):
            issues.append(f"{lang}.json: file not found")
            continue
        d = bundles[lang]
        missing = set(en.keys()) - set(d.keys())
        if missing:
            issues.append(f"{lang}.json: missing {len(missing)} key(s)")
        for key, en_value in en.items():
            localized_value = d.get(key, "")
            if placeholders(en_value) != placeholders(localized_value):
                issues.append(
                    f"{lang}.json: placeholder mismatch for {key}: "
                    f"expected {sorted(placeholders(en_value))}, got {sorted(placeholders(localized_value))}"
                )

    for key, en_value in en.items():
        xc_entry = xcstrings.get(key)
        if not xc_entry:
            issues.append(f"Localizable.xcstrings: missing key {key}")
            continue
        localizations = xc_entry.get("localizations", {})
        for lang in SUPPORTED_LANGUAGES:
            value = localizations.get(lang, {}).get("stringUnit", {}).get("value")
            expected = bundles[lang].get(key)
            if value != expected:
                issues.append(f"Localizable.xcstrings: {key}/{lang} out of sync")

    if issues:
        for i in issues:
            print(f"  FAIL: {i}")
        sys.exit(1)
    else:
        print("  All translations OK")


if __name__ == "__main__":
    main()
