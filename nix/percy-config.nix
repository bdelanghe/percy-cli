# nix/percy-config.nix
# Configuration for Percy CLI build: versions and tools

{ pkgs }:

let
  version = "0.0.1";

in {
  inherit version;

  # Note: Bun is used for package management, builds, and binary compilation
  # The binary is compiled with `bun build --compile` which creates a standalone executable
}

