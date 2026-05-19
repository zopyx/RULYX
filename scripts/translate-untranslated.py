#!/usr/bin/env python3
"""
Translate untranslated entries in all non-English JSON files.

Uses deep_translator.GoogleTranslator (free, no API key needed).
Falls back to original English text on any failure.
"""

import json
import os
import re
import sys
import time

from deep_translator import GoogleTranslator

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCALIZATIONS_DIR = os.path.join(PROJECT_ROOT, "Sources", "Shared", "Localizations")

# Map JSON filenames → Google Translate language codes
LANG_MAP = {
    "de": "de", "fr": "fr", "it": "it", "ja": "ja", "zh": "zh-CN",
    "es": "es", "pt": "pt", "ko": "ko", "ru": "ru", "ar": "ar",
    "nl": "nl", "pl": "pl", "tr": "tr", "th": "th", "vi": "vi",
}

PLACEHOLDER_RE = re.compile(r"\{[^}]+\}")


def protect(text: str) -> tuple[str, dict[str, str]]:
    mapping = {}
    for i, ph in enumerate(PLACEHOLDER_RE.findall(text)):
        token = f"RULYXPH{i}TOKEN"
        mapping[token] = ph
        text = text.replace(ph, token, 1)
    return text, mapping


def restore(text: str, mapping: dict[str, str]) -> str:
    for token, original in mapping.items():
        text = text.replace(token, original)
    return text


def translate_one(translator: GoogleTranslator, text: str, retries: int = 2) -> str:
    for attempt in range(retries):
        try:
            protected, mapping = protect(text)
            result = translator.translate(protected)
            if result:
                return restore(result, mapping)
            return text
        except Exception:
            if attempt < retries - 1:
                time.sleep(3)
            else:
                return text


def main():
    with open(os.path.join(LOCALIZATIONS_DIR, "en.json")) as f:
        en = json.load(f)

    for lang_code, gt_code in LANG_MAP.items():
        path = os.path.join(LOCALIZATIONS_DIR, f"{lang_code}.json")
        with open(path) as f:
            d = json.load(f)

        untranslated = [k for k in en if d.get(k) == en[k] and k in d]
        if not untranslated:
            print(f"{lang_code}: nothing to translate")
            continue

        print(f"{lang_code}: translating {len(untranslated)} entries...")

        translator = GoogleTranslator(source="en", target=gt_code)
        translated_count = 0

        for i, key in enumerate(untranslated):
            original = en[key]
            if not original.strip():
                continue

            result = translate_one(translator, original)
            if result != original:
                d[key] = result
                translated_count += 1

            if (i + 1) % 10 == 0:
                print(f"  {lang_code}: {i+1}/{len(untranslated)} translated {translated_count}")
                time.sleep(2)

        with open(path, "w") as f:
            json.dump(d, f, indent=2, ensure_ascii=False)
            f.write("\n")

        print(f"  {lang_code}: done ({translated_count}/{len(untranslated)} translated)")
        time.sleep(5)

    print("All translations complete.")


if __name__ == "__main__":
    main()
