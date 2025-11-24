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

# Note: Environment setup (gsed, pkg, PATH, yarn, node) is handled by Nix flake
# This script assumes all tools are available via runtimeInputs

# Cleanup: Remove old build artifacts
echo "Cleaning up old build artifacts..."
rm -f percy run run-linux-arm64 run-macos-arm64 run-win-arm64.exe percy.exe percy-osx
rm -f percy-linux.zip percy-osx.zip

# Build source
echo "Installing dependencies..."
yarn install

echo "Building source..."
yarn build

# Guard: Verify build artifacts exist
[ ! -d ./packages/cli/dist ] && {
  echo "Error: Build failed - ./packages/cli/dist not found"
  exit 1
}

# Remove type from package.json files
echo "Removing 'type: module' from package.json files..."
gsed -i '/"type": "module",/{s///;h};${x;/./{x;q0};x;q1}' ./package.json

# Create array of package.json files
array=($(ls -d ./packages/*/package.json))

# Delete package.json filepath where type module is not defined
delete=(./packages/dom/package.json ./packages/sdk-utils/package.json)

# Remove type module from package.json where present
for package in "${array[@]}"
do
  [ -z "$package" ] && continue
  # Skip packages that are in delete list
  skip=false
  for del in "${delete[@]}"
  do
    [ "$package" = "$del" ] && skip=true && break
  done
  [ "$skip" = "true" ] && continue
  gsed -i '/"type": "module",/{s///;h};${x;/./{x;q0};x;q1}' "$package"
done

# Patch the CLI entry file
echo "Patching CLI entry file..."
# Guard: Verify source file exists before patching
[ ! -f ./packages/cli/dist/percy.js ] && {
  echo "Error: ./packages/cli/dist/percy.js not found"
  exit 1
}

echo "import { cli } from '@percy/cli';\
$(cat ./packages/cli/dist/percy.js)" > ./packages/cli/dist/percy.js

# Guard: Verify run.cjs exists before patching
[ ! -f ./packages/cli/bin/run.cjs ] && {
  echo "Error: ./packages/cli/bin/run.cjs not found"
  exit 1
}

gsed -i '/Update NODE_ENV for executable/{s//\nprocess.env.NODE_ENV = "executable";/;h};${x;/./{x;q0};x;q1}' ./packages/cli/bin/run.cjs

# Convert ES6 code to cjs
echo "Converting to CommonJS..."
npm run build_cjs

# Guard: Verify build_cjs artifacts exist
[ ! -d ./build ] && {
  echo "Error: Build failed - ./build directory not found"
  exit 1
}

cp -R ./build/* packages/

# Guard: Verify files were copied
[ ! -f ./packages/cli/bin/run.js ] && {
  echo "Error: ./packages/cli/bin/run.js not found after copy"
  exit 1
}

# Remove type: module from package.json files after copy (build files are CommonJS)
echo "Removing 'type: module' from package.json files (after build copy)..."
gsed -i '/"type": "module",/{s///;h};${x;/./{x;q0};x;q1}' ./package.json

# Remove type module from all package package.json files
for package in ./packages/*/package.json
do
  [ ! -f "$package" ] && continue
  # Skip packages that don't have type: module
  [ "$package" = "./packages/dom/package.json" ] && continue
  [ "$package" = "./packages/sdk-utils/package.json" ] && continue
  gsed -i '/"type": "module",/{s///;h};${x;/./{x;q0};x;q1}' "$package"
done

# Create executable (Linux ARM64 only)
echo "Building Linux ARM64 executable with pkg..."
# Guard: Verify run.js exists before building
[ ! -f ./packages/cli/bin/run.js ] && {
  echo "Error: ./packages/cli/bin/run.js not found"
  exit 1
}

pkg ./packages/cli/bin/run.js \
  --targets node18-linux-arm64

# Rename executable
echo "Renaming executable..."
# Preflight: Check for expected executable files
[ -f run-linux-arm64 ] && mv run-linux-arm64 percy && chmod +x percy
[ -f run ] && [ ! -f percy ] && mv run percy && chmod +x percy

# Guard: Exit if executable not found (right after pkg completes)
[ ! -f percy ] && {
  echo "Error: Expected executable file 'run-linux-arm64' or 'run' not found"
  exit 1
}

# Verify architecture
echo "Verifying binary architecture..."
# Guard: Verify binary is ARM64
file percy | grep -q "aarch64\|ARM" || {
  echo "✗ percy (Linux) is NOT ARM64"
  file percy
  exit 1
}

echo "✓ percy (Linux) is ARM64"
file percy

# Create zip file
echo "Creating zip file..."
zip percy-linux.zip percy

# Guard: Verify zip file was created
[ ! -f percy-linux.zip ] && {
  echo "Error: Failed to create percy-linux.zip"
  exit 1
}

# Disable trap before explicit cleanup to avoid running twice
trap - EXIT
cleanup

echo ""
echo "✓ Build complete!"
echo "  Binary: ./percy"
echo "  Archive: ./percy-linux.zip"
echo ""
echo "Test the binary with: ./percy --version"

