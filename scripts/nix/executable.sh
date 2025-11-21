#!/bin/bash
set -e -o pipefail

# Detect if running with act (local GitHub Actions runner)
function is_act() {
  # Act sets ACT environment variable or runs in Docker without GITHUB_ACTIONS
  if [ -n "${ACT:-}" ]; then
    return 0
  fi
  # Check if we're in a Docker container but not in real GitHub Actions
  if [ -f /.dockerenv ] && [ -z "${GITHUB_ACTIONS:-}" ]; then
    return 0
  fi
  # Check cgroup for Docker (Linux containers)
  if [ -f /proc/self/cgroup ] && grep -qa docker /proc/self/cgroup 2>/dev/null && [ -z "${GITHUB_ACTIONS:-}" ]; then
    return 0
  fi
  return 1
}

# Check for --no-sign flag or NO_SIGN environment variable
NO_SIGN=false
if [[ "$1" == "--no-sign" ]] || [[ "${NO_SIGN:-}" == "true" ]]; then
  NO_SIGN=true
elif is_act; then
  # Auto-detect act and set NO_SIGN if not explicitly set
  echo "Detected act (local GitHub Actions runner). Auto-enabling --no-sign for Linux-only build."
  NO_SIGN=true
fi

function check_dependencies() {
  if ! command -v gsed &> /dev/null; then
    echo "Error: gsed (GNU sed) is required but not found." >&2
    echo "Please install it with: brew install gnu-sed" >&2
    echo "Or ensure it's available in your PATH." >&2
    exit 1
  fi
}

# Parse architecture configuration
# LINUX_ARCHS: comma-separated list (e.g., "x64,arm64") - defaults to "x64"
# MACOS_ARCHS: comma-separated list (e.g., "x64,arm64") - defaults to "x64"
function parse_arch_config() {
  # Default architectures
  export LINUX_ARCHS="${LINUX_ARCHS:-x64}"
  export MACOS_ARCHS="${MACOS_ARCHS:-x64}"
  
  echo "Architecture configuration:"
  echo "  Linux: $LINUX_ARCHS"
  echo "  macOS: $MACOS_ARCHS"
}

# Convert architecture list to pkg target format
# Input: "x64,arm64" -> Output: "node20-linux-x64 node20-linux-arm64"
function archs_to_pkg_targets() {
  local platform=$1
  local archs=$2
  local targets=""
  
  IFS=',' read -ra ARCH_ARRAY <<< "$archs"
  for arch in "${ARCH_ARRAY[@]}"; do
    arch=$(echo "$arch" | xargs)  # trim whitespace
    if [ -n "$targets" ]; then
      targets="$targets "
    fi
    targets="${targets}node20-${platform}-${arch}"
  done
  
  echo "$targets"
}

function check_secrets() {
  # Check Apple signing secrets
  local has_apple=false
  if [ -n "$APPLE_DEV_CERT" ] && [ -n "$APPLE_CERT_KEY" ] && [ -n "$APPLE_ID_USERNAME" ] && [ -n "$APPLE_ID_KEY" ] && [ -n "$APPLE_TEAM_ID" ]; then
    has_apple=true
  fi

  # Check Windows signing secrets
  local has_windows=false
  if [ -n "$WINDOWS_CERT" ] && [ -n "$WINDOWS_CERT_KEY" ]; then
    has_windows=true
  fi

  # Export for use in other functions
  export HAS_APPLE_SECRETS=$has_apple
  export HAS_WINDOWS_SECRETS=$has_windows

  # Validate secrets based on NO_SIGN flag
  if [ "$NO_SIGN" = false ]; then
    # If not skipping signing, we need secrets to build all platforms
    if [ "$has_apple" = false ] && [ "$has_windows" = false ]; then
      echo "Error: NO_SIGN is false but no signing secrets are available." >&2
      echo "Either set NO_SIGN=true or provide signing secrets:" >&2
      echo "  For Apple: APPLE_DEV_CERT, APPLE_CERT_KEY, APPLE_ID_USERNAME, APPLE_ID_KEY, APPLE_TEAM_ID" >&2
      echo "  For Windows: WINDOWS_CERT, WINDOWS_CERT_KEY" >&2
      exit 1
    fi
    # If we're on macOS and building all platforms, we should have Apple secrets
    if [[ "$OSTYPE" == "darwin"* ]] && [ "$has_apple" = false ]; then
      echo "Warning: Running on macOS without Apple signing secrets. macOS executable will not be signed." >&2
    fi
  else
    echo "Skipping signing (NO_SIGN=true). Building Linux-only executable."
  fi
}

function setup_temp_dir() {
  # Create temporary directory for build modifications
  BUILD_TMP=$(mktemp -d)
  export BUILD_TMP
  echo "Using temporary build directory: $BUILD_TMP"
  
  # Set trap to cleanup on exit (temp directory and signing artifacts)
  trap cleanup EXIT INT TERM
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

  # Modify run.cjs in temp
  gsed -i '/Update NODE_ENV for executable/{s//\nprocess.env.NODE_ENV = "executable";/;h};${x;/./{x;q0};x;q1}' ./packages/cli/bin/run.cjs

  # Convert ES6 code to cjs (runs in temp directory)
  npm run build_cjs
  cp -R ./build/* packages/
}

function build_linux_only() {
  echo "Building Linux executable only (NO_SIGN=true)"
  # Build in temp directory
  cd "$BUILD_TMP"
  
  # Get pkg targets for Linux architectures
  local pkg_targets=$(archs_to_pkg_targets "linux" "$LINUX_ARCHS")
  local arch_count=$(echo "$LINUX_ARCHS" | tr ',' '\n' | wc -l | tr -d ' ')
  
  echo "Building Linux executables for: $LINUX_ARCHS"
  npx -y pkg ./packages/cli/bin/run.js -t "$pkg_targets" -d
  
  # Handle output files based on number of architectures
  if [ "$arch_count" -eq 1 ]; then
    # Single architecture: pkg creates 'run' or 'run-linux'
    if [ -f run-linux ]; then
      mv run-linux percy && chmod +x percy
    else
      mv run percy && chmod +x percy
    fi
    zip percy-linux.zip percy
    mv percy-linux.zip "$ORIGINAL_DIR/"
    mv percy "$ORIGINAL_DIR/" 2>/dev/null || true
  else
    # Multiple architectures: pkg creates 'run-linux', 'run-linux-arm64', etc.
    IFS=',' read -ra ARCH_ARRAY <<< "$LINUX_ARCHS"
    for arch in "${ARCH_ARRAY[@]}"; do
      arch=$(echo "$arch" | xargs)  # trim whitespace
      local exe_name="run-linux"
      if [ "$arch" != "x64" ]; then
        exe_name="run-linux-${arch}"
      fi
      
      if [ -f "$exe_name" ]; then
        local output_name="percy-linux-${arch}"
        mv "$exe_name" "$output_name" && chmod +x "$output_name"
        zip "${output_name}.zip" "$output_name"
        mv "${output_name}.zip" "$ORIGINAL_DIR/"
        mv "$output_name" "$ORIGINAL_DIR/" 2>/dev/null || true
      fi
    done
  fi
}

function build_windows_only() {
  echo "Building Windows executable only (NO_SIGN=true)"
  # Build in temp directory
  cd "$BUILD_TMP"
  
  echo "Building Windows executable for: x64"
  npx -y pkg ./packages/cli/bin/run.js -t node20-win-x64 -d
  
  # Handle Windows executable
  if [ -f run-win.exe ]; then
    mv run-win.exe percy.exe
    mv percy.exe "$ORIGINAL_DIR/" 2>/dev/null || true
  else
    echo "Error: Windows executable not found after pkg build" >&2
    ls -la
    exit 1
  fi
}

function build_all_platforms() {
  echo "Building all platform executables (signing secrets available)"
  # Build in temp directory
  cd "$BUILD_TMP"
  
  # Build all targets: Linux, macOS, and Windows
  # For Linux and macOS, we support multiple architectures
  local linux_targets=$(archs_to_pkg_targets "linux" "$LINUX_ARCHS")
  local macos_targets=$(archs_to_pkg_targets "macos" "$MACOS_ARCHS")
  local all_targets="${linux_targets} ${macos_targets} node20-win-x64"
  
  echo "Building executables for all platforms"
  echo "  Linux: $LINUX_ARCHS"
  echo "  macOS: $MACOS_ARCHS"
  echo "  Windows: x64"
  npx -y pkg ./packages/cli/bin/run.js -t "$all_targets" -d
  
  # Handle Linux executables (multiple architectures possible)
  local linux_arch_count=$(echo "$LINUX_ARCHS" | tr ',' '\n' | wc -l | tr -d ' ')
  if [ "$linux_arch_count" -eq 1 ]; then
    if [ -f run-linux ]; then
      mv run-linux percy && chmod +x percy
      zip percy-linux.zip percy
      mv percy "$ORIGINAL_DIR/" 2>/dev/null || true
      mv percy-linux.zip "$ORIGINAL_DIR/"
    fi
  else
    IFS=',' read -ra ARCH_ARRAY <<< "$LINUX_ARCHS"
    for arch in "${ARCH_ARRAY[@]}"; do
      arch=$(echo "$arch" | xargs)  # trim whitespace
      local exe_name="run-linux"
      if [ "$arch" != "x64" ]; then
        exe_name="run-linux-${arch}"
      fi
      
      if [ -f "$exe_name" ]; then
        local output_name="percy-linux-${arch}"
        mv "$exe_name" "$output_name" && chmod +x "$output_name"
        zip "${output_name}.zip" "$output_name"
        mv "${output_name}.zip" "$ORIGINAL_DIR/"
        mv "$output_name" "$ORIGINAL_DIR/" 2>/dev/null || true
      fi
    done
  fi
  
  # Handle macOS executables (multiple architectures possible)
  local macos_arch_count=$(echo "$MACOS_ARCHS" | tr ',' '\n' | wc -l | tr -d ' ')
  if [ "$macos_arch_count" -eq 1 ]; then
    if [ -f run-macos ]; then
      mv run-macos percy-osx && chmod +x percy-osx
      mv percy-osx "$ORIGINAL_DIR/" 2>/dev/null || true
    fi
  else
    IFS=',' read -ra ARCH_ARRAY <<< "$MACOS_ARCHS"
    for arch in "${ARCH_ARRAY[@]}"; do
      arch=$(echo "$arch" | xargs)  # trim whitespace
      local exe_name="run-macos"
      if [ "$arch" != "x64" ]; then
        exe_name="run-macos-${arch}"
      fi
      
      if [ -f "$exe_name" ]; then
        local output_name="percy-osx-${arch}"
        mv "$exe_name" "$output_name" && chmod +x "$output_name"
        mv "$output_name" "$ORIGINAL_DIR/" 2>/dev/null || true
      fi
    done
  fi
  
  # Handle Windows executable (single architecture for now)
  if [ -f run-win.exe ]; then
    mv run-win.exe percy.exe
    mv percy.exe "$ORIGINAL_DIR/" 2>/dev/null || true
  fi
}

function sign_macos() {
  # Work in original directory for signing (needs access to scripts/files)
  cd "$ORIGINAL_DIR"
  
  if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "Skipping macOS signing and notarization (not on macOS)"
    # Package all macOS executables without signing
    local macos_arch_count=$(echo "$MACOS_ARCHS" | tr ',' '\n' | wc -l | tr -d ' ')
    if [ "$macos_arch_count" -eq 1 ]; then
      if [ -f percy-osx ]; then
        mv percy-osx percy
        zip percy-osx.zip percy
      fi
    else
      IFS=',' read -ra ARCH_ARRAY <<< "$MACOS_ARCHS"
      for arch in "${ARCH_ARRAY[@]}"; do
        arch=$(echo "$arch" | xargs)  # trim whitespace
        if [ -f "percy-osx-${arch}" ]; then
          zip "percy-osx-${arch}.zip" "percy-osx-${arch}"
        fi
      done
    fi
    return
  fi

  if [ "$HAS_APPLE_SECRETS" = false ]; then
    echo "Skipping macOS signing and notarization (no Apple signing secrets)"
    # Package all macOS executables without signing
    local macos_arch_count=$(echo "$MACOS_ARCHS" | tr ',' '\n' | wc -l | tr -d ' ')
    if [ "$macos_arch_count" -eq 1 ]; then
      if [ -f percy-osx ]; then
        mv percy-osx percy
        zip percy-osx.zip percy
      fi
    else
      IFS=',' read -ra ARCH_ARRAY <<< "$MACOS_ARCHS"
      for arch in "${ARCH_ARRAY[@]}"; do
        arch=$(echo "$arch" | xargs)  # trim whitespace
        if [ -f "percy-osx-${arch}" ]; then
          zip "percy-osx-${arch}.zip" "percy-osx-${arch}"
        fi
      done
    fi
    return
  fi

  echo "Signing and notarizing macOS executables..."
  echo "$APPLE_DEV_CERT" | base64 -d > AppleDevIDApp.p12

  security create-keychain -p percy percy.keychain
  security import AppleDevIDApp.p12 -t agg -k percy.keychain -P $APPLE_CERT_KEY -A
  security list-keychains -s ~/Library/Keychains/percy.keychain
  security default-keychain -s ~/Library/Keychains/percy.keychain
  security unlock-keychain -p "percy" ~/Library/Keychains/percy.keychain
  security set-keychain-settings -t 3600 -l ~/Library/Keychains/percy.keychain
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k percy ~/Library/Keychains/percy.keychain-db

  # Sign all macOS executables
  local macos_arch_count=$(echo "$MACOS_ARCHS" | tr ',' '\n' | wc -l | tr -d ' ')
  if [ "$macos_arch_count" -eq 1 ]; then
    if [ -f percy-osx ]; then
      codesign --force --verbose=4 -s "Developer ID Application: BrowserStack Inc ($APPLE_TEAM_ID)" --options runtime --entitlements scripts/files/entitlement.plist --keychain ~/Library/Keychains/percy.keychain percy-osx
      mv percy-osx percy
      zip percy-osx.zip percy
      xcrun notarytool submit --apple-id "$APPLE_ID_USERNAME" --password $APPLE_ID_KEY --team-id $APPLE_TEAM_ID percy-osx.zip --wait
    fi
  else
    IFS=',' read -ra ARCH_ARRAY <<< "$MACOS_ARCHS"
    for arch in "${ARCH_ARRAY[@]}"; do
      arch=$(echo "$arch" | xargs)  # trim whitespace
      if [ -f "percy-osx-${arch}" ]; then
        codesign --force --verbose=4 -s "Developer ID Application: BrowserStack Inc ($APPLE_TEAM_ID)" --options runtime --entitlements scripts/files/entitlement.plist --keychain ~/Library/Keychains/percy.keychain "percy-osx-${arch}"
        zip "percy-osx-${arch}.zip" "percy-osx-${arch}"
        xcrun notarytool submit --apple-id "$APPLE_ID_USERNAME" --password $APPLE_ID_KEY --team-id $APPLE_TEAM_ID "percy-osx-${arch}.zip" --wait
      fi
    done
  fi
}

function cleanup() {
  # Clean up temp directory (handled by trap, but explicit cleanup here too)
  if [ -n "${BUILD_TMP:-}" ] && [ -d "$BUILD_TMP" ]; then
    rm -rf "$BUILD_TMP"
  fi
  
  # Clean up signing artifacts in original directory
  if [ -f AppleDevIDApp.p12 ]; then
    rm AppleDevIDApp.p12
  fi
  if [ "$NO_SIGN" = false ] && [ -f ~/Library/Keychains/percy.keychain-db ]; then
    security delete-keychain ~/Library/Keychains/percy.keychain-db 2>/dev/null || true
  fi
}

# Main execution
# Save original directory
ORIGINAL_DIR=$(pwd)
export ORIGINAL_DIR

check_dependencies
parse_arch_config
check_secrets
setup_temp_dir
prepare_build

if [ "$NO_SIGN" = true ]; then
  # Detect platform and build accordingly
  if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]] || [[ -n "$WINDIR" ]]; then
    build_windows_only
  else
    build_linux_only
  fi
else
  build_all_platforms
  sign_macos
fi

cleanup