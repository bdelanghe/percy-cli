# nix/percy-config.nix
# Configuration for Percy CLI build: versions and tools

{ pkgs }:

let
  version = "0.0.1";

  # bun2nix installation strategy
  # Options:
  #   "mkDerivation" - Use bun2nix.mkDerivation with automatic hook (default, bun2nix v2)
  #   "manual-cache" - Manually set up cache and run bun install (fallback)
  # Note: Bun may still attempt to download package manifests even with offline cache
  # This is a known Bun limitation - it requires manifest metadata from the registry
  # Set to "manual-cache" if you need to bypass the hook or if mkDerivation fails
  bunInstallStrategy = "mkDerivation";

in {
  inherit version bunInstallStrategy;

  # Note: Bun is used for package management, builds, and binary compilation
  # The binary is compiled with `bun build --compile` which creates a standalone executable
}

