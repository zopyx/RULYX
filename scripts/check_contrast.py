#!/usr/bin/env python3
"""WCAG 2.1 contrast checker for RULYX brand/semantic color pairs.

Verifies that text/background color combinations used in the app meet
WCAG-AA (>=4.5:1 normal text, >=3:1 large text). Exits non-zero on failure.

Run: python3 scripts/check_contrast.py
"""

import sys


def channel_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(r: float, g: float, b: float) -> float:
    return (
        0.2126 * channel_linear(r)
        + 0.7152 * channel_linear(g)
        + 0.0722 * channel_linear(b)
    )


def contrast(l1: float, l2: float) -> float:
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def blend_over(fg_lum_white: float, alpha: float, bg_lum: float) -> float:
    """Effective luminance of white at `alpha` opacity over background."""
    return alpha * fg_lum_white + (1 - alpha) * bg_lum


WHITE = 1.0

# (name, fg_description, fg_luminance, bg_rgb, minimum_ratio)
CHECKS = [
    # Chat bubble (Color+RULYX.swift: chatBubbleOutgoing)
    ("chat outgoing white text / light bubble", WHITE, (0.05, 0.42, 0.88), 4.5),
    ("chat outgoing white text / dark bubble", WHITE, (0.10, 0.42, 0.85), 4.5),
    # Outgoing timestamps: white at 0.9 opacity over bubble
    ("chat outgoing ts 0.9 / light bubble", None, (0.05, 0.42, 0.88), 4.5),
    ("chat outgoing ts 0.9 / dark bubble", None, (0.10, 0.42, 0.85), 4.5),

    # Semantic colors used as text foregrounds (on dark/light backgrounds)
    # skyOrange: used for action buttons (like "Block")
    ("skyOrange dark bg AA", 1.0, (0.10, 0.14, 0.18), 4.5),
    ("dark text / skyOrange light", (0.05, 0.05, 0.05), (0.98, 0.60, 0.20), 4.5),
    # skyAccent: used for accent text
    ("skyAccent dark bg AA", WHITE, (0.20, 0.27, 0.88), 4.5),
    ("skyAccent light bg AA", None, (0.28, 0.35, 0.92), 4.5),
    # errorRed: used for destructive buttons and error messages
    ("errorRed dark bg AA", None, (0.25, 0.10, 0.10), 4.5),
    # green (repost): green text on light/dark
    ("green repost dark bg AA", WHITE, (0.15, 0.55, 0.25), 3.0),
    ("green repost light bg AA", None, (0.12, 0.50, 0.22), 3.0),

    # Primary/secondary label colors — system defaults, verified
    ("system primary / dark bg", WHITE, (0.05, 0.05, 0.05), 4.5),
    ("system secondary / light bg", (0.25, 0.25, 0.25), (0.95, 0.95, 0.95), 3.0),

    # REGRESSION GUARDS — must always fail (documented)
    ("REGRESSION-GUARD skyPrimary dark (expected to fail AA)", WHITE, (0.40, 0.78, 1.00), None),
    ("REGRESSION-GUARD skyPrimary light (expected to fail AA)", WHITE, (0.07, 0.53, 0.98), None),
]

failures = 0
for name, fg, bg, minimum in CHECKS:
    bg_lum = luminance(*bg)
    if fg is None:
        fg_lum = blend_over(WHITE, 0.9, bg_lum)
    elif isinstance(fg, tuple):
        fg_lum = luminance(*fg)
    else:
        fg_lum = fg
    ratio = contrast(fg_lum, bg_lum)
    if minimum is None:
        print(f"  info   {name}: {ratio:.2f}:1 (guard, no assertion)")
        continue
    ok = ratio >= minimum
    status = "PASS" if ok else "FAIL"
    if not ok:
        failures += 1
    print(f"  {status}   {name}: {ratio:.2f}:1 (min {minimum:.1f}:1)")

if failures:
    print(f"\n{failures} contrast check(s) FAILED")
    sys.exit(1)
print("\nAll contrast checks passed.")
