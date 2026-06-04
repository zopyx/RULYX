#!/usr/bin/env bash

# Upload a local build to App Store Connect directly (no Xcode Cloud, no TestFlight).
# Accepts an .xcarchive or .ipa, exports/validates as needed, then submits.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/release"
EXPORT_OPTIONS_PLIST="$BUILD_DIR/ExportOptions.plist"

usage() {
  cat <<'EOF'
Usage:
  scripts/upload-to-asc.sh <path.xcarchive|path.ipa> [--method apple-id|api-key]

Examples:
  # Upload from xcarchive (exports IPA first)
  scripts/upload-to-asc.sh build/release/RULYX-1.0.8-62.xcarchive

  # Upload IPA directly
  scripts/upload-to-asc.sh build/release/export/RULYX.ipa

  # Upload with Apple ID + app-specific password (simplest)
  scripts/upload-to-asc.sh RULYX.ipa --method apple-id

  # Upload with App Store Connect API key (default)
  scripts/upload-to-asc.sh RULYX.ipa --method api-key

Requirements (apple-id method):
  Set these env vars:
    ASC_USERNAME      — your Apple ID email
    ASC_PASSWORD      — app-specific password (generate at appleid.apple.com)

Requirements (api-key method):
  Set these env vars:
    ASC_API_KEY_ID    — key ID from App Store Connect → Users and Access → Keys
    ASC_API_ISSUER_ID — issuer ID from the same page

  Key file must be at:
    ~/.appstoreconnect/private_keys/AuthKey_<ASC_API_KEY_ID>.p8
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command xcodebuild
require_command xcrun

INPUT_PATH=""
METHOD="api-key"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --method)
      METHOD="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      INPUT_PATH="$1"
      shift
      ;;
  esac
done

if [[ -z "$INPUT_PATH" ]]; then
  echo "Error: specify an .xcarchive or .ipa path" >&2
  usage
  exit 1
fi

if [[ ! -e "$INPUT_PATH" ]]; then
  echo "Error: file not found: $INPUT_PATH" >&2
  exit 1
fi

IPA_PATH=""

case "$INPUT_PATH" in
  *.xcarchive)
    echo "==> Exporting IPA from archive: $INPUT_PATH"
    mkdir -p "$BUILD_DIR"
    cat >"$EXPORT_OPTIONS_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
PLIST
    xcodebuild -exportArchive \
      -archivePath "$INPUT_PATH" \
      -exportPath "$BUILD_DIR/export" \
      -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
      -allowProvisioningUpdates
    IPA_PATH="$BUILD_DIR/export/$(basename "${INPUT_PATH%.xcarchive}").ipa"
    if [[ ! -f "$IPA_PATH" ]]; then
      IPA_PATH="$BUILD_DIR/export/*.ipa"
    fi
    # Find the actual IPA
    IPA_PATH=$(find "$BUILD_DIR/export" -name '*.ipa' -maxdepth 1 | head -1)
    if [[ -z "$IPA_PATH" || ! -f "$IPA_PATH" ]]; then
      echo "Error: IPA export produced no .ipa file in $BUILD_DIR/export" >&2
      exit 1
    fi
    echo "   IPA: $IPA_PATH"
    ;;
  *.ipa)
    IPA_PATH="$INPUT_PATH"
    ;;
  *)
    echo "Error: input must be an .xcarchive or .ipa file" >&2
    exit 1
    ;;
esac

echo "==> Validating IPA: $IPA_PATH"

case "$METHOD" in
  api-key)
    : "${ASC_API_KEY_ID:?Set ASC_API_KEY_ID}"
    : "${ASC_API_ISSUER_ID:?Set ASC_API_ISSUER_ID}"

    KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_API_KEY_ID}.p8"
    if [[ ! -f "$KEY_PATH" ]]; then
      echo "Error: API key not found at: $KEY_PATH" >&2
      echo "Place AuthKey_${ASC_API_KEY_ID}.p8 there or use --method apple-id." >&2
      exit 1
    fi

    echo "==> Uploading with App Store Connect API key"
    xcrun iTMSTransporter \
      -m upload \
      -assetFile "$IPA_PATH" \
      -apiKey "$ASC_API_KEY_ID" \
      -apiIssuer "$ASC_API_ISSUER_ID" \
      -v informational
    ;;
  apple-id)
    : "${ASC_USERNAME:?Set ASC_USERNAME to your Apple ID email}"
    : "${ASC_PASSWORD:?Set ASC_PASSWORD to an app-specific password}"

    echo "==> Uploading with Apple ID"
    xcrun altool --upload-app \
      -f "$IPA_PATH" \
      -u "$ASC_USERNAME" \
      -p "$ASC_PASSWORD" \
      --verbose
    ;;
  *)
    echo "Error: unknown method '$METHOD'. Use 'api-key' or 'apple-id'." >&2
    exit 1
    ;;
esac

echo "==> Upload submitted to App Store Connect"
