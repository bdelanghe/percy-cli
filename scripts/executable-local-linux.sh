#!/bin/bash
set -e -o pipefail

# Local build script for Linux ARM64 only
# Skips macOS/Windows signing steps that require credentials

echo "Building Linux ARM64 executable locally..."

# Check for required dependencies
if ! command -v gsed &> /dev/null; then
  echo "Error: gsed (gnu-sed) is required but not found."
  echo "If using Nix, run: nix develop"
  echo "Otherwise, install gsed: brew install gnu-sed (macOS) or apt-get install gsed (Linux)"
  exit 1
fi

if ! command -v pkg &> /dev/null; then
  echo "Installing pkg..."
  npm install -g pkg
fi

# Build source
echo "Installing dependencies..."
yarn install

echo "Building source..."
yarn build

# Remove type from package.json files
echo "Removing 'type: module' from package.json files..."
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

# Patch the CLI entry file
echo "Patching CLI entry file..."
echo "import { cli } from '@percy/cli';\
$(cat ./packages/cli/dist/percy.js)" > ./packages/cli/dist/percy.js

gsed -i '/Update NODE_ENV for executable/{s//\nprocess.env.NODE_ENV = "executable";/;h};${x;/./{x;q0};x;q1}' ./packages/cli/bin/run.cjs

# Convert ES6 code to cjs
echo "Converting to CommonJS..."
npm run build_cjs
cp -R ./build/* packages/

# Create executable (Linux ARM64 only)
echo "Building Linux ARM64 executable with pkg..."
pkg ./packages/cli/bin/run.js \
  --targets node18-linux-arm64 \
  -d

# Rename executable
echo "Renaming executable..."
mv run-linux-arm64 percy && chmod +x percy

# Verify architecture
echo "Verifying binary architecture..."
if file percy | grep -q "aarch64\|ARM"; then
  echo "✓ percy (Linux) is ARM64"
  file percy
else
  echo "✗ percy (Linux) is NOT ARM64"
  file percy
  exit 1
fi

# Create zip file
echo "Creating zip file..."
zip percy-linux.zip percy

echo ""
echo "✓ Build complete!"
echo "  Binary: ./percy"
echo "  Archive: ./percy-linux.zip"
echo ""
echo "Test the binary with: ./percy --version"

