#!/bin/bash
set -e -o pipefail

# Local build script for Linux ARM64 only
# Skips macOS/Windows signing steps that require credentials

# Cleanup function to restore git changes and remove temporary files
cleanup() {
  local exit_code=$?
  echo "Cleaning up..."
  set +e  # Disable exit on error for cleanup
  git restore . 2>/dev/null || true
  rm -f packages/dom/src/serialize-blob-urls.js packages/dom/test/serialize-blob-urls.test.js 2>/dev/null || true
  set -e  # Re-enable exit on error
  return $exit_code  # Return the original exit code
}

# Set trap to run cleanup on exit (success or error)
trap cleanup EXIT

echo "Building Linux ARM64 executable locally..."

# Check for required dependencies - use gsed if available, otherwise use sed (GNU sed in Nix)
# In Nix environment, gsed should be available via runtimeInputs
SED_CMD=""
if command -v gsed >/dev/null 2>&1; then
  SED_CMD=gsed
elif command -v sed >/dev/null 2>&1; then
  # Test if it's GNU sed by checking for --version support
  if sed --version >/dev/null 2>&1; then
    SED_CMD=sed
  fi
fi

if [ -z "$SED_CMD" ]; then
  echo "Error: gsed or GNU sed is required but not found."
  echo "Current PATH: $PATH"
  echo "If using Nix, ensure gsed is in PATH"
  echo "Otherwise, install gsed: brew install gnu-sed (macOS) or apt-get install gsed (Linux)"
  exit 1
fi

echo "Using sed command: $SED_CMD"

if ! command -v pkg > /dev/null 2>&1; then
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

# Recreate array of package.json files for second pass
array2=($(ls -d ./packages/*/package.json))
delete2=(./packages/dom/package.json ./packages/sdk-utils/package.json)
for del in ${delete2[@]}
do
   array2=("${array2[@]/$del}")
done

# Remove type module from package.json where present
for package in "${array2[@]}"
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

# Disable trap before explicit cleanup to avoid running twice
trap - EXIT
cleanup

echo ""
echo "✓ Build complete!"
echo "  Binary: ./percy"
echo "  Archive: ./percy-linux.zip"
echo ""
echo "Test the binary with: ./percy --version"

