# default.nix
# Main package definition for Percy CLI built with pkg via Nix

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

    # Disable the hook's automatic install phase and do it manually
    # This gives us more control over the install process
    dontBunInstall = true;

    buildPhase = ''
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"

      # Set up offline cache from bunDeps
      # The bun2nix hook should have set BUN_INSTALL_CACHE, but we'll ensure it's set
      export BUN_INSTALL_CACHE="${bunDeps}"

      echo "Installing dependencies from bun2nix cache at: $BUN_INSTALL_CACHE"
      echo "Cache contents:"
      ls -la "$BUN_INSTALL_CACHE" | head -20 || true

      # Install dependencies using the offline cache
      bun install --frozen-lockfile --no-save --backend=symlink

      export PATH="$PWD/node_modules/.bin:$PATH"

      # Build using Bun workspace scripts
      bun run build_cjs

      # Build CJS output (via babel or existing script)
      BABEL_ENV=dev babel packages -d build || true

      if [ -d build ]; then
        cp -R build/* packages/
      fi
    '';

    installPhase = ''
      mkdir -p "$out"
      cp -R . "$out"
    '';
  };

  # Layer 3: prepared CLI tree (patched for pkg)
  preparedCli = import ./nix/prepared-cli.nix {
    inherit pkgs nodeTree;
    version = cfg.version;
  };

  pkgWrapper = import ./nix/pkg-wrapper.nix { inherit pkgs; };

  # Layer 4: pkg-wrapped CLI binary
  percyCli = pkgWrapper {
    pname       = "percy-cli";
    version     = cfg.version;
    pkgTarget   = cfg.pkgTargetFor system;
    preparedCli = preparedCli;
    entrypoint  = "./packages/cli/bin/run.cjs";
    binaryName  = "percy";
  };

in
percyCli

