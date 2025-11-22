# default.nix
# Main package definition for Percy CLI built with Bun compile via Nix

{ pkgs, bunNix }:

let
  # Extract system from pkgs
  system = pkgs.stdenv.hostPlatform.system;

  # Configuration
  cfg = import ./nix/percy-config.nix { inherit pkgs; };

  # Check for bun.lock and bun.nix in source before building
  # These should be generated outside Nix and committed to version control
  hasBunLock = builtins.pathExists ./bun.lock;
  hasBunNix  = builtins.pathExists bunNix;

  _ = if !hasBunLock || !hasBunNix then
    throw ''

      Missing Bun lock artifacts in source:

        bun.lock present: ${toString hasBunLock}
        bun.nix present:  ${toString hasBunNix}

      To fix:
        bun install                    # Generates bun.lock
        bunx bun2nix -o bun.nix       # Generates bun.nix from bun.lock
        # Or use Nix app:
        nix run .#update-lockfiles
        git add bun.lock bun.nix

    ''
  else
    null;

  # Layer 1: Patched source tree
  srcPatched = import ./nix/src-patched.nix {
    inherit pkgs;
    version = cfg.version;
  };

  # Offline Bun dependency cache from bun.nix
  # Use pkgs.bun2nix from overlay (tag 2.0.1 should have passthru attributes)
  # Use the bunNix parameter passed from flake.nix
  bunDeps = pkgs.bun2nix.fetchBunDeps {
    bunNix = bunNix;
  };

  # Layer 2: node tree build using bun2nix
  # Use stdenv.mkDerivation with bun2nix.hook for offline installs
  nodeTree = pkgs.stdenv.mkDerivation {
    pname   = "percy-cli-node-tree";
    version = cfg.version;
    src     = srcPatched;

    nativeBuildInputs = [
      pkgs.bun
      pkgs.nodejs
      pkgs.bun2nix.hook  # setup hook for offline installs (from overlay)
    ];

    # bun2nix.hook uses this to find the offline cache
    inherit bunDeps;
    buildPhase = ''
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"

      # bun2nix.hook should have already installed dependencies in bunNodeModulesInstallPhase
      # Verify dependencies are installed
      if [ ! -d node_modules ]; then
        echo "Error: node_modules not found after bun2nix.hook install phase" >&2
        echo "This suggests the hook's bunNodeModulesInstallPhase failed" >&2
        exit 1
      fi

      echo "Dependencies installed successfully by bun2nix.hook from offline cache"
      export PATH="$PWD/node_modules/.bin:$PATH"

      # Build using Bun workspace scripts (ESM output)
      # This builds all packages in the monorepo as ESM
      bun run build
    '';

    installPhase = ''
      mkdir -p "$out"
      cp -R . "$out"
    '';
  };

  # Layer 3: Bun-compiled binary
  percyCli = pkgs.stdenv.mkDerivation {
    pname   = "percy-cli";
    version = cfg.version;
    src     = nodeTree;

    nativeBuildInputs = [
      pkgs.bun
    ];

    buildPhase = ''
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"
      export PATH="$PWD/node_modules/.bin:$PATH"

      # Build the binary using Bun compile
      # This creates a standalone executable with Bun runtime
      bun build ./packages/cli/src/bin.js --compile --outfile=./percy
    '';

    installPhase = ''
      mkdir -p "$out/bin"
      cp ./percy "$out/bin/percy"
      chmod +x "$out/bin/percy"
    '';

    meta = {
      description = "Percy CLI - standalone binary compiled with Bun";
      mainProgram = "percy";
      license = pkgs.lib.licenses.mit;
    };
  };

in
percyCli

