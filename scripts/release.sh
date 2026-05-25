#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="RULYX"
PROJECT_PATH="$ROOT_DIR/${PROJECT_NAME}.xcodeproj"
SCHEME="$PROJECT_NAME"
BUILD_DIR="$ROOT_DIR/build/release"
EXPORT_OPTIONS_PLIST="$BUILD_DIR/ExportOptions.plist"
# Xcode's IPA export path expects Apple's patched system rsync implementation.
SYSTEM_PATH_PREFIX="/usr/bin:/bin:/usr/sbin:/sbin"

UPLOAD=1

usage() {
  cat <<'EOF'
Usage:
  scripts/release.sh [--no-upload]

What it does:
  1. Runs xcodegen generate
  2. Archives a Release build for generic iOS
  3. Exports an App Store Connect IPA
  4. Optionally uploads the IPA with Transporter

Upload requirements:
  Set these environment variables before running:
    ASC_API_KEY_ID
    ASC_API_ISSUER_ID

  Transporter must be able to find:
    ~/.appstoreconnect/private_keys/AuthKey_<ASC_API_KEY_ID>.p8

Examples:
  scripts/release.sh
  scripts/release.sh --no-upload
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-upload)
      UPLOAD=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command xcodegen
require_command xcodebuild
require_command xcrun

read_project_value() {
  local key="$1"
  awk -F'"' -v pattern="$key" '
    $0 ~ pattern ":" {
      print $2
      exit
    }
  ' "$ROOT_DIR/project.yml"
}

MARKETING_VERSION="$(read_project_value 'MARKETING_VERSION')"
CURRENT_PROJECT_VERSION="$(read_project_value 'CURRENT_PROJECT_VERSION')"

if [[ -z "$MARKETING_VERSION" || -z "$CURRENT_PROJECT_VERSION" ]]; then
  echo "Failed to read MARKETING_VERSION or CURRENT_PROJECT_VERSION from project.yml" >&2
  exit 1
fi

ARCHIVE_PATH="$BUILD_DIR/${PROJECT_NAME}-${MARKETING_VERSION}-${CURRENT_PROJECT_VERSION}.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
IPA_PATH="$EXPORT_PATH/${PROJECT_NAME}.ipa"

if [[ "$UPLOAD" -eq 1 ]]; then
  : "${ASC_API_KEY_ID:?Set ASC_API_KEY_ID before uploading}"
  : "${ASC_API_ISSUER_ID:?Set ASC_API_ISSUER_ID before uploading}"

  KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_API_KEY_ID}.p8"
  if [[ ! -f "$KEY_PATH" ]]; then
    echo "Transporter API key not found at: $KEY_PATH" >&2
    echo "Place AuthKey_${ASC_API_KEY_ID}.p8 there or run with --no-upload." >&2
    exit 1
  fi
fi

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

cat >"$EXPORT_OPTIONS_PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
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
EOF

echo "==> Generating Xcode project"
(
  cd "$ROOT_DIR"
  PATH="$SYSTEM_PATH_PREFIX:$PATH" xcodegen generate
)

echo "==> Archiving ${PROJECT_NAME} ${MARKETING_VERSION} (${CURRENT_PROJECT_VERSION})"
PATH="$SYSTEM_PATH_PREFIX:$PATH" xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  archive

echo "==> Exporting IPA"
PATH="$SYSTEM_PATH_PREFIX:$PATH" xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  -allowProvisioningUpdates

if [[ ! -f "$IPA_PATH" ]]; then
  echo "IPA not found at expected path: $IPA_PATH" >&2
  exit 1
fi

echo "==> IPA created at: $IPA_PATH"

if [[ "$UPLOAD" -eq 1 ]]; then
  echo "==> Uploading with Transporter"
  PATH="$SYSTEM_PATH_PREFIX:$PATH" xcrun iTMSTransporter \
    -m upload \
    -assetFile "$IPA_PATH" \
    -apiKey "$ASC_API_KEY_ID" \
    -apiIssuer "$ASC_API_ISSUER_ID" \
    -v informational

  echo "==> Upload submitted to App Store Connect"
else
  echo "==> Upload skipped"
fi
