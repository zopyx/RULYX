#!/bin/bash
# Pre-push hook — guards against common architecture violations.
# Fails the push if violations are found.
# Install: ln -sf ../../scripts/pre-push-check.sh .git/hooks/pre-push

set -euo pipefail

echo "→ Running pre-push architecture checks..."

VIOLATIONS=0

# 1. No views importing service implementations directly (LiveBlueskyClient, etc.)
echo "  Checking view→service coupling..."
FORBIDDEN_IMPORTS=("LiveBlueskyClient" "BlueskyRequestExecutor" "BlueskySessionService")
VIEW_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '^Sources/(Features|App)/' | grep '\.swift$' || true)
for file in $VIEW_FILES; do
    filename=$(basename "$file")
    # Exempt files that are allowed
    [[ "$filename" == "AppDependencies.swift" ]] && continue
    [[ "$filename" == "RULYXApp.swift" ]] && continue
    [[ "$filename" == "RootView.swift" ]] && continue
    [[ "$filename" == *"ViewModel"* ]] && continue

    for symbol in "${FORBIDDEN_IMPORTS[@]}"; do
        if grep -q "$symbol" "$file" 2>/dev/null; then
            echo "    ✗ $file references $symbol — views must use ViewModels or protocol types"
            VIOLATIONS=$((VIOLATIONS + 1))
        fi
    done
done

# 2. Localization key sync
echo "  Checking localization key sync..."
if git diff --cached --name-only | grep -q 'Sources/Shared/Localizations/en.json'; then
    if python3 scripts/validate-translations.py 2>/dev/null; then
        echo "    ✓ All language files in sync"
    else
        echo "    ✗ Translation validation failed — sync keys before pushing"
        VIOLATIONS=$((VIOLATIONS + 1))
    fi
fi

# 3. SwiftFormat compliance
echo "  Checking SwiftFormat..."
SWIFT_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.swift$' || true)
if [ -n "$SWIFT_FILES" ]; then
    if command -v swiftformat &>/dev/null; then
        if swiftformat --lint $SWIFT_FILES 2>/dev/null; then
            echo "    ✓ SwiftFormat OK"
        else
            echo "    ✗ SwiftFormat violations found — run swiftformat Sources Tests"
            VIOLATIONS=$((VIOLATIONS + 1))
        fi
    else
        echo "    ⚠ swiftformat not installed, skipping"
    fi
fi

echo ""
if [ $VIOLATIONS -eq 0 ]; then
    echo "✓ All pre-push checks passed"
    exit 0
else
    echo "✗ $VIOLATIONS violation(s) found — fix before pushing"
    exit 1
fi
