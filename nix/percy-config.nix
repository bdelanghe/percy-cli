# nix/percy-config.nix
# Configuration for Percy CLI build: versions and tools

{ pkgs }:

let
  version = "0.0.1";

  # bun2nix installation strategy
  # Options:
  #   "mkBunDerivation" - Use bun2nix.mkBunDerivation with automatic hook (default)
  #   "manual-cache" - Manually set up cache and run bun install (fallback if hook fails)
  # Set to "manual-cache" if mkBunDerivation hook is not working correctly
  bunInstallStrategy = "mkBunDerivation";

in {
  inherit version bunInstallStrategy;

  # Note: Bun is used for package management, builds, and binary compilation
  # The binary is compiled with `bun build --compile` which creates a standalone executable
}

