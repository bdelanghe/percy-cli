# nix/pkg-wrapper.nix
# Reusable function to wrap a Node.js CLI with pkg
# Given a prepared CLI tree and a JS entrypoint, builds a platform-specific binary

{ pkgs }:

{ pname
, version
, pkgTarget
, preparedCli
, entrypoint ? "./packages/cli/bin/run.cjs"
, binaryName ? pname
}:

let
  inherit (pkgs) stdenv;
  pkgTool = pkgs.nodePackages.pkg;
  node    = pkgs.nodejs_20;
in

stdenv.mkDerivation {
  inherit pname version;
  src = preparedCli;
  sourceRoot = ".";

  nativeBuildInputs = [
    node
    pkgTool
  ];

  NODE_ENV = "production";

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    mkdir -p "$out/bin"
    export NODE_PATH="$PWD/node_modules:$NODE_PATH"

    pkg ${entrypoint} -t ${pkgTarget} -d

    for name in run-${pkgTarget} run-linux run-macos run; do
      if [ -f "$name" ]; then
        mv "$name" "$out/bin/${binaryName}"
        chmod +x "$out/bin/${binaryName}"
        exit 0
      fi
    done

    echo "Error: pkg did not produce expected binary" >&2
    ls -la
    exit 1
  '';

  meta = {
    description = "${pname} packaged via pkg";
    mainProgram = binaryName;
    license = pkgs.lib.licenses.mit;
  };
}

