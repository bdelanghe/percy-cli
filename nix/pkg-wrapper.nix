# nix/pkg-wrapper.nix
# Reusable function to wrap a Node.js CLI with pkg
# Given a node tree and a JS entrypoint, builds a platform-specific binary

{ pkgs }:

{ pname
, version
, pkgTarget
, nodeTree
, entrypoint ? "./packages/cli/bin/run.cjs"
, patchCli ? true
, binaryName ? pname
}:

let
  inherit (pkgs) stdenv gnused;
  pkgTool = pkgs.nodePackages.pkg;
  node    = pkgs.nodejs_20;
in

stdenv.mkDerivation {
  inherit pname version;
  src = nodeTree;
  sourceRoot = "libexec/${pname}-node-tree";

  nativeBuildInputs = [
    node
    gnused
    pkgTool
  ];

  NODE_ENV = "production";

  patchPhase = ''
    ${if patchCli then ''
      if [ -f packages/cli/dist/percy.js ]; then
        {
          echo "import { cli } from '@percy/cli';"
          cat packages/cli/dist/percy.js
        } > packages/cli/dist/percy.js.new
        mv packages/cli/dist/percy.js.new packages/cli/dist/percy.js
      fi

      if [ -f packages/cli/bin/run.cjs ] && \
         ! grep -q 'process.env.NODE_ENV = "executable";' packages/cli/bin/run.cjs; then
        sed -i '1a process.env.NODE_ENV = "executable";' packages/cli/bin/run.cjs
      fi
    '' else ""}
  '';

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

