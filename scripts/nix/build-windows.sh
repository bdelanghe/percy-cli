#!/bin/bash
set -e -o pipefail

# Windows-specific build script for Percy CLI
# This script builds Windows executables without signing
# Usage: ./scripts/nix/build-windows.sh

function check_dependencies() {
  if ! command -v gsed &> /dev/null; then
    echo "Error: gsed (GNU sed) is required but not found." >&2
    echo "Please install it with: choco install gnu-sed" >&2
    echo "Or ensure it's available in your PATH." >&2
    exit 1
  fi
}

function setup_temp_dir() {
  # Create temporary directory for build modifications
  BUILD_TMP=$(mktemp -d)
  export BUILD_TMP
  echo "Using temporary build directory: $BUILD_TMP"
  
  # Set trap to cleanup temp directory on exit
  trap "rm -rf '$BUILD_TMP'" EXIT INT TERM
}

function prepare_build() {
  # Build in original directory (read-only operations)
  yarn install
  yarn build

  # Copy necessary files to temp directory
  echo "Copying files to temporary directory..."
  cp -R packages "$BUILD_TMP/"
  cp package.json "$BUILD_TMP/"
  cp babel.config.cjs "$BUILD_TMP/" 2>/dev/null || true
  cp -R node_modules "$BUILD_TMP/" 2>/dev/null || true
  
  # Copy build output if it exists
  if [ -d build ]; then
    cp -R build "$BUILD_TMP/"
  fi

  # Work in temp directory from now on
  cd "$BUILD_TMP"

  # Remove type from package.json files in temp
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
      gsed -i '/"type": "module",/{s///;h};${x;/./{x;q0};x;q1}' "$package"
    fi
  done

  # Modify percy.js in temp
  echo "import { cli } from '@percy/cli';\
  $(cat ./packages/cli/dist/percy.js)" > ./packages/cli/dist/percy.js

  # Ensure NODE_ENV is set in run.cjs (matches Nix build behavior)
  if [ -f ./packages/cli/bin/run.cjs ] && \
     ! grep -q 'process.env.NODE_ENV = "executable";' ./packages/cli/bin/run.cjs; then
    gsed -i '1a process.env.NODE_ENV = "executable";' ./packages/cli/bin/run.cjs
  fi

  # Convert ES6 code to cjs (runs in temp directory)
  npm run build_cjs
  cp -R ./build/* packages/
}

function build_windows() {
  echo "Building Windows executable"
  # Build in temp directory
  cd "$BUILD_TMP"
  
  echo "Building Windows executable for: x64"
  npx -y pkg ./packages/cli/bin/run.js -t node20-win-x64 -d
  
  # Handle Windows executable
  if [ -f run-win.exe ]; then
    mv run-win.exe percy.exe
    mv percy.exe "$ORIGINAL_DIR/"
    # Verify the file exists at destination before reporting success
    if [ ! -f "$ORIGINAL_DIR/percy.exe" ]; then
      echo "Error: Failed to move executable to $ORIGINAL_DIR/" >&2
      exit 1
    fi
    echo "Windows executable built successfully: $ORIGINAL_DIR/percy.exe"
  else
    echo "Error: Windows executable not found after pkg build" >&2
    ls -la
    exit 1
  fi
}

function cleanup() {
  # Clean up temp directory (handled by trap, but explicit cleanup here too)
  if [ -n "${BUILD_TMP:-}" ] && [ -d "$BUILD_TMP" ]; then
    rm -rf "$BUILD_TMP"
  fi
}

# Main execution
# Save original directory
ORIGINAL_DIR=$(pwd)
export ORIGINAL_DIR

check_dependencies
setup_temp_dir
prepare_build
build_windows
cleanup

