# default.nix
# Main package definition for Percy CLI
# Provides two build options:
# - Option A: Nix-wrapped Node (percy-cli-node) - simpler, uses Node to run ESM
# - Option B: Bun-compiled binary (percy-cli) - true native binary with embedded Bun runtime

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
        git add bun.lockb bun.nix

    ''
  else
    null;

  # Layer 1: Patched source tree
  srcPatched = import ./nix/src-patched.nix {
    inherit pkgs;
    version = cfg.version;
  };

  # Layer 2: node tree build using bun2nix
  # Use mkBunDerivation which automatically handles offline cache setup
  # mkBunDerivation will fetch dependencies from bun.nix internally
  nodeTree = pkgs.bun2nix.mkBunDerivation {
    pname   = "percy-cli-node-tree";
    version = cfg.version;
    src     = srcPatched;

    # mkBunDerivation uses bunNix to fetch and set up the offline cache automatically
    bunNix = bunNix;

    # mkBunDerivation automatically runs bun install with offline cache
    # We just need to run the build after dependencies are installed
    buildPhase = ''
      runHook preBuild
      
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"
      export PATH="$PWD/node_modules/.bin:$PATH"

      # Verify dependencies are installed (mkBunDerivation should have done this)
      if [ ! -d node_modules ]; then
        echo "Error: node_modules not found after mkBunDerivation install phase" >&2
        exit 1
      fi

      echo "Dependencies installed successfully by mkBunDerivation from offline cache"
      
      # Build using Bun workspace scripts (ESM output)
      # This builds all packages in the monorepo as ESM
      bun run build
      
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -R . "$out"
      runHook postInstall
    '';
  };

  # Option A: Nix-wrapped Node CLI
  # Simple wrapper that runs Node on the built ESM entrypoint
  percyCliNode = pkgs.writeShellScriptBin "percy" ''
    exec ${pkgs.nodejs}/bin/node ${nodeTree}/packages/cli/dist/index.js "$@"
  '';

  # Option B: Bun-compiled binary
  # True native binary with embedded Bun runtime
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
{
  # Option A: Nix-wrapped Node (simpler, works directly with ESM)
  percy-cli-node = percyCliNode;
  
  # Option B: Bun-compiled binary (true native binary)
  percy-cli = percyCli;
  
  # Default to Bun-compiled binary for backward compatibility
  default = percyCli;
}

