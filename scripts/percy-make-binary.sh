#!/bin/bash
set -euo pipefail

# scripts/percy-make-binary.sh
# Reusable binary packaging script for Percy CLI
# Can be used in Nix builds or CI release jobs
#
# Usage: ./scripts/percy-make-binary.sh <pkg-target> <output-path>
# Example: ./scripts/percy-make-binary.sh node20-linux-x64 ./percy

if [ $# -ne 2 ]; then
  echo "Usage: $0 <pkg-target> <output-path>" >&2
  echo "Example: $0 node20-linux-x64 ./percy" >&2
  exit 1
fi

target="$1"
outbin="$2"

# Ensure output directory exists
mkdir -p "$(dirname "$outbin")"

# Run pkg to create the binary
npx -y pkg ./packages/cli/bin/run.js -t "$target" -d

# pkg can name outputs differently; handle the common cases
for name in "run-$target" run-linux run-macos run; do
  if [ -f "$name" ]; then
    mv "$name" "$outbin"
    chmod +x "$outbin"
    exit 0
  fi
done

echo "Error: pkg did not produce expected binary" >&2
echo "Expected one of: run-$target, run-linux, run-macos, run" >&2
ls -la
exit 1

