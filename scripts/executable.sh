#!/bin/bash
set -e -o pipefail

function cleanup {
  rm -rf build
  rm AppleDevIDApp.p12
  security delete-keychain percy.keychain
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

# Create executables (ARM64 for all OSes)
pkg ./packages/cli/bin/run.js \
  --targets node18-linux-arm64,node18-macos-arm64,node18-win-arm64 \
  -d

# Rename executables (ARM64)
mv run-linux-arm64 percy && chmod +x percy
mv run-macos-arm64 percy-osx && chmod +x percy-osx
mv run-win-arm64.exe percy.exe && chmod +x percy.exe

# Verify architectures
echo "Verifying binary architectures..."
file percy-osx | grep -q "arm64" && echo "✓ percy-osx is ARM64" || echo "✗ percy-osx is NOT ARM64"
file percy | grep -q "aarch64\|ARM" && echo "✓ percy (Linux) is ARM64" || echo "✗ percy (Linux) is NOT ARM64"

# Sign & Notrize mac app
echo "$APPLE_DEV_CERT" | base64 -d > AppleDevIDApp.p12

security create-keychain -p percy percy.keychain
security import AppleDevIDApp.p12 -t agg -k percy.keychain -P $APPLE_CERT_KEY -A
security list-keychains -s ~/Library/Keychains/percy.keychain
security default-keychain -s ~/Library/Keychains/percy.keychain
security unlock-keychain -p "percy" ~/Library/Keychains/percy.keychain
security set-keychain-settings -t 3600 -l ~/Library/Keychains/percy.keychain
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k percy ~/Library/Keychains/percy.keychain-db

codesign  --force --verbose=4 -s "Developer ID Application: BrowserStack Inc ($APPLE_TEAM_ID)" --options runtime --entitlements scripts/files/entitlement.plist --keychain ~/Library/Keychains/percy.keychain percy-osx

# Create zip file for uploading as assets
zip percy-linux.zip percy
mv percy-osx percy
zip percy-osx.zip percy

xcrun notarytool submit --apple-id "$APPLE_ID_USERNAME" --password $APPLE_ID_KEY --team-id $APPLE_TEAM_ID percy-osx.zip --wait

cleanup
