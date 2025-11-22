#!/bin/bash
set -e -o pipefail

function cleanup {
  rm -rf build
  rm AppleDevIDApp.p12
  security delete-keychain percy.keychain
}

brew install gnu-sed

bun install
bun run build

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

# Build executables using Bun compile
# Bun compile creates platform-specific binaries
echo "Building executables with Bun compile..."

# Build for current platform (Bun compile targets the current OS/arch)
# Note: For cross-platform builds, you may need to run this on each target platform
# or use Bun's cross-compilation features if available
bun build ./packages/cli/src/bin.js --compile --outfile=./percy

# Determine platform and rename accordingly
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  # Linux
  mv percy percy-linux || cp percy percy-linux
  chmod +x percy-linux
  # For macOS and Windows, you'd need to build on those platforms or use cross-compilation
  echo "Built Linux executable: percy-linux"
  echo "Note: macOS and Windows executables require building on those platforms"
elif [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  mv percy percy-osx || cp percy percy-osx
  chmod +x percy-osx
  echo "Built macOS executable: percy-osx"
  echo "Note: Linux and Windows executables require building on those platforms"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
  # Windows
  mv percy percy.exe || cp percy percy.exe
  chmod +x percy.exe
  echo "Built Windows executable: percy.exe"
  echo "Note: Linux and macOS executables require building on those platforms"
else
  echo "Warning: Unknown platform $OSTYPE, keeping default name 'percy'"
  chmod +x percy
fi

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
