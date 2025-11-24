#!/bin/bash
set -e -o pipefail

# Local build script for Linux ARM64 only
# Skips macOS/Windows signing steps that require credentials

echo "Building Linux ARM64 executable locally..."

# Check for required dependencies - use gsed if available, otherwise use sed (GNU sed in Nix)
if command -v gsed &> /dev/null; then
  SED_CMD=gsed
elif command -v sed &> /dev/null && sed --version &> /dev/null; then
  # Check if sed is GNU sed (has --version flag)
  SED_CMD=sed
else
  echo "Error: gsed or GNU sed is required but not found."
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
$SED_CMD -i '/"type": "module",/{s///;h};${x;/./{x;q0};x;q1}' ./package.json

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
    $SED_CMD -i '/"type": "module",/{s///;h};${x;/./{x;q0};x;q1}' $package
  fi
done

# Patch the CLI entry file
echo "Patching CLI entry file..."
echo "import { cli } from '@percy/cli';\
$(cat ./packages/cli/dist/percy.js)" > ./packages/cli/dist/percy.js

$SED_CMD -i '/Update NODE_ENV for executable/{s//\nprocess.env.NODE_ENV = "executable";/;h};${x;/./{x;q0};x;q1}' ./packages/cli/bin/run.cjs

# Convert ES6 code to cjs
echo "Converting to CommonJS..."
npm run build_cjs
cp -R ./build/* packages/

# Remove type from package.json files again (after copy, to ensure they're all updated)
echo "Removing 'type: module' from package.json files (after build)..."
$SED_CMD -i '/"type": "module",/{s///;h};${x;/./{x;q0};x;q1}' ./package.json
for package in "${array[@]}"
do
  if [ ! -z "$package" ]
  then
    $SED_CMD -i '/"type": "module",/{s///;h};${x;/./{x;q0};x;q1}' $package
  fi
done

# Create executable (Linux ARM64 only)
echo "Building Linux ARM64 executable with pkg..."
pkg ./packages/cli/bin/run.js \
  --targets node18-linux-arm64

# Rename executable
echo "Renaming executable..."
if [ -f run-linux-arm64 ]; then
  mv run-linux-arm64 percy && chmod +x percy
elif [ -f run ]; then
  mv run percy && chmod +x percy
else
  echo "Error: Expected executable file 'run-linux-arm64' or 'run' not found"
  exit 1
fi

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

# Cleanup: restore git changes and remove temporary files
echo "Cleaning up..."
git restore .
rm -f packages/dom/src/serialize-blob-urls.js packages/dom/test/serialize-blob-urls.test.js

echo ""
echo "✓ Build complete!"
echo "  Binary: ./percy"
echo "  Archive: ./percy-linux.zip"
echo ""
echo "Test the binary with: ./percy --version"

