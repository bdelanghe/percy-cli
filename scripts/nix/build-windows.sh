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
  # Change back to original directory first to avoid deletion issues on Windows/Git Bash
  trap "cd '$ORIGINAL_DIR' 2>/dev/null || true; rm -rf '$BUILD_TMP'" EXIT INT TERM
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
  
  # Verify node_modules was copied successfully (required for build_cjs)
  if [ ! -d "$BUILD_TMP/node_modules" ]; then
    echo "Error: Failed to copy node_modules to temporary build directory" >&2
    echo "The build requires node_modules to exist in $BUILD_TMP" >&2
    exit 1
  fi
  
  # Copy build output if it exists
  if [ -d build ]; then
    cp -R build "$BUILD_TMP/"
  fi

  # Work in temp directory from now on
  cd "$BUILD_TMP"

  # Remove type from package.json files in temp
  # Use simple pattern that doesn't fail if pattern is not found (matches flake.nix behavior)
  gsed -i '/"type": "module",/d' ./package.json

  # Create array of package.json files
  array=($(ls -d ./packages/*/package.json))

  # Delete package.json filepath where type module is not defined
  delete=(./packages/dom/package.json ./packages/sdk-utils/package.json)
  for del in ${delete[@]}
  do
     array=("${array[@]/$del}")
  done

  # Remove type module from package.json where present
  # Use simple pattern that doesn't fail if pattern is not found (matches flake.nix behavior)
  for package in "${array[@]}"
  do
    if [ ! -z "$package" ]
    then
      gsed -i '/"type": "module",/d' "$package"
    fi
  done

  # Modify percy.js in temp
  if [ -f ./packages/cli/dist/percy.js ]; then
    {
      echo "import { cli } from '@percy/cli';"
      cat ./packages/cli/dist/percy.js
    } > ./packages/cli/dist/percy.js.new
    mv ./packages/cli/dist/percy.js.new ./packages/cli/dist/percy.js
  fi

  # Ensure NODE_ENV is set in run.cjs (matches Nix build behavior)
  if [ -f ./packages/cli/bin/run.cjs ] && \
     ! grep -q 'process.env.NODE_ENV = "executable";' ./packages/cli/bin/run.cjs; then
    gsed -i '1a process.env.NODE_ENV = "executable";' ./packages/cli/bin/run.cjs
  fi

  # Convert ES6 code to cjs (runs in temp directory)
  npm run build_cjs || true
  if [ -d build ]; then
    cp -R ./build/* packages/
  fi
}

function build_windows() {
  echo "Building Windows executable"
  # Build in temp directory
  cd "$BUILD_TMP"
  
  echo "Building Windows executable for: x64"
  # Note: package.json specifies bin as ./bin/run.cjs (not run.js)
  npx -y pkg ./packages/cli/bin/run.cjs -t node20-win-x64 -d
  
  # Handle Windows executable
  if [ -f run-win.exe ]; then
    mv run-win.exe percy.exe || {
      echo "Error: Failed to rename run-win.exe to percy.exe" >&2
      exit 1
    }
    mv percy.exe "$ORIGINAL_DIR/" || {
      echo "Error: Failed to move executable to $ORIGINAL_DIR/" >&2
      exit 1
    }
    # Verify the file exists at destination before reporting success
    if [ ! -f "$ORIGINAL_DIR/percy.exe" ]; then
      echo "Error: Executable not found at destination after move: $ORIGINAL_DIR/percy.exe" >&2
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
  # Change back to original directory before removing temp directory
  # This prevents issues on Windows/Git Bash where deleting the current directory can fail
  if [ -n "${ORIGINAL_DIR:-}" ]; then
    cd "$ORIGINAL_DIR" || true
  fi
  
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

