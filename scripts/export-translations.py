#!/usr/bin/env python3
"""Export all translation keys with English text and all translations as JSON."""

import json
import os
import re
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCALIZATIONS_DIR = os.path.join(PROJECT_ROOT, "Sources", "Shared", "Localizations")

SUPPORTED_LANGUAGES = [
    "en", "de", "fr", "it", "ja", "zh", "es", "pt",
    "ko", "ru", "ar", "nl", "pl", "tr", "th", "vi",
]

PLACEHOLDER_RE = re.compile(r"\{[^}]+\}")
STRUCTURAL_RE = re.compile(r"^[\s:;,\-–—(){}\[\]/\\.+…]*$")
ALLOWED_UNCHANGED_VALUES = {
    "1 minute",
    "15 minutes",
    "30 minutes",
    "5 minutes",
    "BETA",
    "Bluesky",
    "CSV",
    "Chat",
    "ClearSky",
    "ClearSky GitHub",
    "Debug",
    "Description",
    "Doxxing",
    "Error",
    "Eurosky",
    "Export",
    "Feed AT URI (at://...)",
    "GIF",
    "Images",
    "Info",
    "JSON",
    "Media",
    "Message…",
    "Name",
    "Notifications",
    "OK",
    "Open Source",
    "Regular",
    "Rulyx",
    "System",
    "Tab",
    "Text",
    "Total",
    "Type",
    "Videos",
    "iCloud",
}


def load_translations() -> dict[str, dict[str, str]]:
    bundles: dict[str, dict[str, str]] = {}
    for lang in SUPPORTED_LANGUAGES:
        path = os.path.join(LOCALIZATIONS_DIR, f"{lang}.json")
        if not os.path.exists(path):
            print(f"Warning: {path} not found, skipping", file=sys.stderr)
            continue
        with open(path) as f:
            bundles[lang] = json.load(f)
    return bundles


def is_allowed_unchanged(value: str) -> bool:
    stripped = PLACEHOLDER_RE.sub("", value).strip()
    if value in ALLOWED_UNCHANGED_VALUES:
        return True
    if stripped.startswith("github.com/") or stripped.startswith("did:") or stripped.startswith("DIDs: did:"):
        return True
    if not stripped:
        return True
    if STRUCTURAL_RE.fullmatch(stripped):
        return True
    return False


def build_report(bundles: dict[str, dict[str, str]]) -> dict:
    en = bundles.get("en", {})
    all_keys = sorted(en.keys())

    report = {
        "meta": {
            "languages": SUPPORTED_LANGUAGES,
            "total_keys": len(all_keys),
            "total_languages": len(bundles),
        },
        "keys": {},
    }

    for key in all_keys:
        entry = {
            "en": en.get(key, ""),
        }
        for lang in SUPPORTED_LANGUAGES:
            if lang == "en":
                continue
            bundle = bundles.get(lang, {})
            value = bundle.get(key, "")
            untranslated = (
                value == en.get(key, "")
                and lang != "en"
                and not is_allowed_unchanged(value)
            )
            entry[lang] = {
                "text": value,
                "untranslated": untranslated,
            }
        report["keys"][key] = entry

    return report


def main():
    bundles = load_translations()
    report = build_report(bundles)

    untranslated_count = sum(
        1 for key in report["keys"]
        for lang in SUPPORTED_LANGUAGES
        if lang != "en" and report["keys"][key].get(lang, {}).get("untranslated")
    )

    report["meta"]["untranslated_total"] = untranslated_count

    output_path = os.path.join(PROJECT_ROOT, "translation-report.json")
    with open(output_path, "w") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    print(f"Report written to {output_path}")
    print(f"  Languages: {len(report['meta']['languages'])}")
    print(f"  Total keys: {report['meta']['total_keys']}")
    print(f"  Untranslated entries: {untranslated_count}")


if __name__ == "__main__":
    main()
