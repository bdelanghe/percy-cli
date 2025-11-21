# nix/percy-config.nix
# Configuration for Percy CLI build: versions, tools, and system mappings

{ pkgs }:

let
  version = "0.0.1";

  pkgTargetFor = system: {
    "x86_64-linux"   = "node20-linux-x64";
    "aarch64-linux"  = "node20-linux-arm64";
    "x86_64-darwin"  = "node20-macos-x64";
    "aarch64-darwin" = "node20-macos-arm64";
  }.${system};

in {
  inherit version pkgTargetFor;

  node    = pkgs.nodejs_20;
  pkgTool = pkgs.nodePackages.pkg;
  # Note: lerna is NOT included here - we use the project's lerna from yarn
  # (version 6.0.1) instead of nixpkgs lerna (8.1.2) to avoid version conflicts
}

