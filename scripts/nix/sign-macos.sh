#!/bin/bash
set -e -o pipefail

# Standalone macOS signing and notarization script
# Usage: ./scripts/nix/sign-macos.sh <binary-path> [output-zip-name]
#
# Environment variables required:
#   APPLE_DEV_CERT - Base64-encoded .p12 certificate
#   APPLE_CERT_KEY - Password for the certificate
#   APPLE_ID_USERNAME - Apple ID username for notarization
#   APPLE_ID_KEY - App-specific password for notarization
#   APPLE_TEAM_ID - Apple Team ID

BINARY_PATH="$1"
OUTPUT_ZIP="${2:-percy-osx.zip}"

if [ -z "$BINARY_PATH" ]; then
  echo "Error: Binary path is required" >&2
  echo "Usage: $0 <binary-path> [output-zip-name]" >&2
  exit 1
fi

if [ ! -f "$BINARY_PATH" ]; then
  echo "Error: Binary not found: $BINARY_PATH" >&2
  exit 1
fi

if [[ "$OSTYPE" != "darwin"* ]]; then
  echo "Error: This script must be run on macOS" >&2
  exit 1
fi

# Check for required secrets
if [ -z "$APPLE_DEV_CERT" ] || [ -z "$APPLE_CERT_KEY" ] || \
   [ -z "$APPLE_ID_USERNAME" ] || [ -z "$APPLE_ID_KEY" ] || \
   [ -z "$APPLE_TEAM_ID" ]; then
  echo "Error: Missing required Apple signing secrets" >&2
  echo "Required environment variables:" >&2
  echo "  APPLE_DEV_CERT" >&2
  echo "  APPLE_CERT_KEY" >&2
  echo "  APPLE_ID_USERNAME" >&2
  echo "  APPLE_ID_KEY" >&2
  echo "  APPLE_TEAM_ID" >&2
  exit 1
fi

# Get absolute path to binary and script directory
BINARY_PATH=$(cd "$(dirname "$BINARY_PATH")" && pwd)/$(basename "$BINARY_PATH")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTITLEMENTS="$SCRIPT_DIR/../files/entitlement.plist"

# Define keychain path (use standard location, defined early for cleanup function)
KEYCHAIN_PATH="$HOME/Library/Keychains/percy.keychain"

# Cleanup function
cleanup() {
  # Remove certificate file if it exists
  if [ -f AppleDevIDApp.p12 ]; then
    rm -f AppleDevIDApp.p12
  fi
  # Remove keychain if it exists
  if [ -f "$KEYCHAIN_PATH-db" ]; then
    security delete-keychain "$KEYCHAIN_PATH-db" 2>/dev/null || true
  fi
}

# Set trap to cleanup on exit
trap cleanup EXIT INT TERM

echo "Signing and notarizing macOS binary: $BINARY_PATH"

# Decode and save certificate
echo "$APPLE_DEV_CERT" | base64 -d > AppleDevIDApp.p12

# Create temporary keychain in standard location
security create-keychain -p percy "$KEYCHAIN_PATH"
security import AppleDevIDApp.p12 -t agg -k "$KEYCHAIN_PATH" -P "$APPLE_CERT_KEY" -A
security list-keychains -s "$KEYCHAIN_PATH"
security default-keychain -s "$KEYCHAIN_PATH"
security unlock-keychain -p "percy" "$KEYCHAIN_PATH"
security set-keychain-settings -t 3600 -l "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k percy "$KEYCHAIN_PATH-db"

# Sign the binary
echo "Codesigning binary..."
codesign --force --verbose=4 \
  -s "Developer ID Application: BrowserStack Inc ($APPLE_TEAM_ID)" \
  --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --keychain "$KEYCHAIN_PATH" \
  "$BINARY_PATH"

# Create zip for notarization
echo "Creating zip for notarization..."
zip "$OUTPUT_ZIP" "$BINARY_PATH"

# Notarize
echo "Submitting for notarization..."
xcrun notarytool submit \
  --apple-id "$APPLE_ID_USERNAME" \
  --password "$APPLE_ID_KEY" \
  --team-id "$APPLE_TEAM_ID" \
  "$OUTPUT_ZIP" \
  --wait

echo "Notarization complete. Signed and notarized binary: $BINARY_PATH"
echo "Zipped artifact: $OUTPUT_ZIP"

