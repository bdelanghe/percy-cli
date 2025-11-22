# nix/prepared-cli.nix
# Layer 3: Prepares the CLI tree for pkg by applying CLI-specific patches
# Takes the built node-tree and applies percy.js import and NODE_ENV patches

{ pkgs, nodeTree, version }:

let
  inherit (pkgs) stdenv gnused;
in

stdenv.mkDerivation {
  pname = "percy-cli-prepared";
  inherit version;

  src = nodeTree;
  # Bun's stdenv.mkDerivation outputs directly to the root
  sourceRoot = ".";

  nativeBuildInputs = [ gnused ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    mkdir -p $out
    cp -R . $out
    cd $out

    # Apply percy.js import patch
    if [ -f packages/cli/dist/percy.js ]; then
      {
        echo "import { cli } from '@percy/cli';"
        cat packages/cli/dist/percy.js
      } > packages/cli/dist/percy.js.new
      mv packages/cli/dist/percy.js.new packages/cli/dist/percy.js
    fi

    # Apply NODE_ENV patch to run.cjs
    if [ -f packages/cli/bin/run.cjs ] && \
       ! grep -q 'process.env.NODE_ENV = "executable";' packages/cli/bin/run.cjs; then
      sed -i '1a process.env.NODE_ENV = "executable";' packages/cli/bin/run.cjs
    fi
  '';

  meta = {
    description = "Percy CLI tree prepared for pkg packaging";
    license = pkgs.lib.licenses.mit;
  };
}

