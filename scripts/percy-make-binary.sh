#!/bin/bash
set -euo pipefail

# scripts/percy-make-binary.sh
# Reusable binary compilation script for Percy CLI
# Can be used in Nix builds or CI release jobs
#
# Usage: ./scripts/percy-make-binary.sh <output-path>
# Example: ./scripts/percy-make-binary.sh ./percy
#
# Note: Bun compile builds for the current platform. For cross-platform builds,
# run this script on each target platform or use Bun's cross-compilation features.

if [ $# -ne 1 ]; then
  echo "Usage: $0 <output-path>" >&2
  echo "Example: $0 ./percy" >&2
  exit 1
fi

outbin="$1"

# Ensure output directory exists
mkdir -p "$(dirname "$outbin")"

# Use Bun compile to create a standalone binary
# This compiles for the current platform (OS/arch)
bun build ./packages/cli/src/bin.js --compile --outfile="$outbin"

# Verify the binary was created
if [ ! -f "$outbin" ]; then
  echo "Error: Bun compile did not produce expected binary at $outbin" >&2
  ls -la "$(dirname "$outbin")"
  exit 1
fi

# Ensure executable permissions
chmod +x "$outbin"

echo "Binary compiled successfully: $outbin"

