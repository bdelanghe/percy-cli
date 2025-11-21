#!/bin/bash
set -e -o pipefail

# Check for --skip-sign flag or SKIP_SIGN environment variable
SKIP_SIGN=false
if [[ "$1" == "--skip-sign" ]] || [[ "$1" == "--no-sign" ]] || [[ "${SKIP_SIGN:-}" == "true" ]]; then
  SKIP_SIGN=true
fi

function cleanup {
  rm -rf build
  if [ -f AppleDevIDApp.p12 ]; then
    rm AppleDevIDApp.p12
  fi
  if [ "$SKIP_SIGN" = false ] && [ -d ~/Library/Keychains/percy.keychain ]; then
    security delete-keychain percy.keychain 2>/dev/null || true
  fi
}

brew install gnu-sed
npm install -g pkg

yarn install
yarn build

# Remove type from package.json files
gsed -i '/"type": "module",/{s///;h};${x;/./{x;q0};x;q1}' ./package.json

# Create array of package.json files
array=($(ls -d ./packages/*/package.json))

# Delete package.json filepath where type module is not defined
delete=(./packages/dom/package.json ./packages/sdk-utils/package.json)
for del in ${delete[@]}
do
   array=("${array[@]/$del}")
done

# Remove type module from package.json where present
for package in "${array[@]}"
do
  if [ ! -z "$package" ]
  then
    gsed -i '/"type": "module",/{s///;h};${x;/./{x;q0};x;q1}' $package
  fi
done

echo "import { cli } from '@percy/cli';\
$(cat ./packages/cli/dist/percy.js)" > ./packages/cli/dist/percy.js

gsed -i '/Update NODE_ENV for executable/{s//\nprocess.env.NODE_ENV = "executable";/;h};${x;/./{x;q0};x;q1}' ./packages/cli/bin/run.cjs

# Convert ES6 code to cjs
npm run build_cjs
cp -R ./build/* packages/

# Create executables
pkg ./packages/cli/bin/run.js -d

# Rename executables
mv run-linux percy && chmod +x percy
mv run-macos percy-osx && chmod +x percy-osx
mv run-win.exe percy.exe && chmod +x percy.exe

# Create zip file for uploading as assets
zip percy-linux.zip percy

# Sign & Notarize mac app (only if not skipped and on macOS)
if [ "$SKIP_SIGN" = false ] && [[ "$OSTYPE" == "darwin"* ]] && [ -n "$APPLE_DEV_CERT" ] && [ -n "$APPLE_CERT_KEY" ] && [ -n "$APPLE_ID_USERNAME" ] && [ -n "$APPLE_ID_KEY" ] && [ -n "$APPLE_TEAM_ID" ]; then
  echo "Signing and notarizing macOS executable..."
  echo "$APPLE_DEV_CERT" | base64 -d > AppleDevIDApp.p12

  security create-keychain -p percy percy.keychain
  security import AppleDevIDApp.p12 -t agg -k percy.keychain -P $APPLE_CERT_KEY -A
  security list-keychains -s ~/Library/Keychains/percy.keychain
  security default-keychain -s ~/Library/Keychains/percy.keychain
  security unlock-keychain -p "percy" ~/Library/Keychains/percy.keychain
  security set-keychain-settings -t 3600 -l ~/Library/Keychains/percy.keychain
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k percy ~/Library/Keychains/percy.keychain-db

  codesign  --force --verbose=4 -s "Developer ID Application: BrowserStack Inc ($APPLE_TEAM_ID)" --options runtime --entitlements scripts/files/entitlement.plist --keychain ~/Library/Keychains/percy.keychain percy-osx

  mv percy-osx percy
  zip percy-osx.zip percy

  xcrun notarytool submit --apple-id "$APPLE_ID_USERNAME" --password $APPLE_ID_KEY --team-id $APPLE_TEAM_ID percy-osx.zip --wait
else
  if [ "$SKIP_SIGN" = true ]; then
    echo "Skipping macOS signing and notarization (--skip-sign flag set)"
  elif [[ "$OSTYPE" != "darwin"* ]]; then
    echo "Skipping macOS signing and notarization (not on macOS)"
  else
    echo "Skipping macOS signing and notarization (Apple certificate environment variables not set)"
  fi
  mv percy-osx percy
  zip percy-osx.zip percy
fi

cleanup
