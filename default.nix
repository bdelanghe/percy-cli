# default.nix
# Main package definition for Percy CLI
# Provides two build options:
# - Option A: Nix-wrapped Node (percy-cli-node) - simpler, uses Node to run ESM
# - Option B: Bun-compiled binary (percy-cli) - true native binary with embedded Bun runtime

{ pkgs, bunNix, mkBunDerivation ? null, fetchBunDeps ? null }:

let
  # Extract system from pkgs
  system = pkgs.stdenv.hostPlatform.system;

  # Configuration
  cfg = import ./nix/percy-config.nix { inherit pkgs; };

  # Diagnostic helpers for bun2nix cache
  diagnostics = import ./nix/bun-diagnostics.nix {
    inherit pkgs bunNix;
  };

  # Check for bun.lock and bun.nix in source before building
  # These should be generated outside Nix and committed to version control
  # Note: Bun 1.2+ uses bun.lock (text format) by default
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

  # Verify bunDeps is built (for diagnostics)
  # This ensures the cache derivation exists before we try to use it
  # By referencing it here, we make it a build dependency that can be inspected
  _verifyBunDeps = diagnostics.bunDeps;
  
  # Diagnostic derivation to verify bunDeps structure
  # Build with: nix build .#bun-deps-verify
  bunDepsVerify = pkgs.writeText "bun-deps-verify" ''
    bunDeps derivation path: ${diagnostics.bunDeps}
    bunDeps store path: ${toString diagnostics.bunDeps}
    
    To inspect bunDeps contents:
      nix-store -qR ${toString diagnostics.bunDeps} | head -20
      ls -la ${toString diagnostics.bunDeps}
  '';

  # Layer 2: node tree build using bun2nix v2
  # Choose installation strategy based on config
  # Default uses mkDerivation (bun2nix v2 API), but can fall back to manual cache setup
  nodeTreeBase = if cfg.bunInstallStrategy == "manual-cache" then
    nodeTreeManual
  else
    # Use bun2nix v2 API: fetchBunDeps + mkDerivation
    let
      # Fetch dependencies offline from bun.nix
      bunDeps = if fetchBunDeps != null then
        fetchBunDeps { bunNix = bunNix; }
      else
        pkgs.bun2nix.fetchBunDeps { bunNix = bunNix; };
      
      # Use mkDerivation (v2 API, not mkBunDerivation)
      # mkBunDerivation parameter name is kept for compatibility with flake.nix
      mkBun = if mkBunDerivation != null then mkBunDerivation else pkgs.bun2nix.mkDerivation;
    in
    mkBun {
    pname   = "percy-cli-node-tree";
    version = cfg.version;
    src     = srcPatched;

    # mkDerivation uses bunDeps to set up offline cache automatically
    inherit bunDeps;
    
    # Add diagnostic output before install phase
    # This helps verify what's happening during bunNodeModulesInstallPhase
    preInstall = ''
      # Set up writable directories for Bun (must be before bun install)
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"
      # TMPDIR is already set by Nix, but ensure it's writable
      mkdir -p "$TMPDIR"
      
      echo "" >&2
      echo "=== Pre-Install Diagnostics ===" >&2
      
      # Check if BUN_INSTALL_CACHE_DIR is set (should be set by bunSetInstallCacheDir phase)
      if [ -n "$BUN_INSTALL_CACHE_DIR" ]; then
        echo "✓ BUN_INSTALL_CACHE_DIR is set: $BUN_INSTALL_CACHE_DIR" >&2
        if [ -d "$BUN_INSTALL_CACHE_DIR" ]; then
          echo "✓ Cache directory exists" >&2
          cache_files=$(find "$BUN_INSTALL_CACHE_DIR" -type f 2>/dev/null | wc -l || echo "0")
          echo "  Cache contains $cache_files files" >&2
          
          # Check for expected Bun cache structure
          if find "$BUN_INSTALL_CACHE_DIR" -type d -name "registry.npmjs.org" 2>/dev/null | grep -q .; then
            echo "✓ Found registry.npmjs.org structure in cache" >&2
          else
            echo "⚠ Warning: registry.npmjs.org structure not found in cache" >&2
            echo "  Cache structure may differ from expected format" >&2
          fi
          
          # Show first few cache entries for debugging
          echo "  First 5 cache entries:" >&2
          find "$BUN_INSTALL_CACHE_DIR" -type f 2>/dev/null | head -5 | sed 's/^/    /' >&2 || true
        else
          echo "✗ Cache directory does not exist: $BUN_INSTALL_CACHE_DIR" >&2
        fi
      else
        echo "✗ BUN_INSTALL_CACHE_DIR is not set" >&2
        echo "  This suggests bunSetInstallCacheDir phase may not have run" >&2
      fi
      
      # Check current directory and lockfile
      echo "" >&2
      echo "Current directory: $(pwd)" >&2
      if [ -f bun.lock ]; then
        echo "✓ bun.lock found" >&2
      elif [ -f bun.lockb ]; then
        echo "⚠ bun.lockb found (legacy format)" >&2
      else
        echo "✗ No bun lockfile found" >&2
      fi
      
      echo "=== End Pre-Install Diagnostics ===" >&2
      echo "" >&2
    '';

    # Add diagnostic output after install phase completes
    # This helps verify what happened during bunNodeModulesInstallPhase
    postInstall = ''
      echo "" >&2
      echo "=== Post-Install Diagnostics ===" >&2
      
      # Check if BUN_INSTALL_CACHE_DIR was set (should still be in environment)
      if [ -n "$BUN_INSTALL_CACHE_DIR" ]; then
        echo "✓ BUN_INSTALL_CACHE_DIR was set: $BUN_INSTALL_CACHE_DIR" >&2
        if [ -d "$BUN_INSTALL_CACHE_DIR" ]; then
          cache_files=$(find "$BUN_INSTALL_CACHE_DIR" -type f 2>/dev/null | wc -l || echo "0")
          echo "  Cache contains $cache_files files" >&2
        fi
      else
        echo "⚠ BUN_INSTALL_CACHE_DIR not found in environment (may have been unset)" >&2
      fi
      
      # Verify node_modules was created
      if [ -d node_modules ]; then
        echo "✓ node_modules directory exists" >&2
        node_count=$(find node_modules -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l || echo "0")
        echo "  Found $node_count top-level packages" >&2
        
        # Check if key packages are present
        for pkg in "@percy/cli" "typescript" "vitest"; do
          if [ -d "node_modules/$pkg" ] || find node_modules -type d -name "$pkg" 2>/dev/null | grep -q .; then
            echo "  ✓ Found $pkg" >&2
          fi
        done
      else
        echo "✗ node_modules directory not found" >&2
      fi
      
      echo "=== End Post-Install Diagnostics ===" >&2
      echo "" >&2
    '';

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

  # Use the selected installation strategy
  nodeTree = nodeTreeBase;

  # Fallback: Manual cache setup (Option A from plan)
  # Use this if mkBunDerivation hook is not working correctly
  # This manually sets up the cache and runs bun install
  nodeTreeManual = pkgs.stdenv.mkDerivation {
    pname   = "percy-cli-node-tree-manual";
    version = cfg.version;
    src     = srcPatched;

    nativeBuildInputs = [
      pkgs.bun
      diagnostics.checkCacheSetup
    ];

    # Manually set up offline cache (bypassing bun2nix hook)
    preInstall = ''
      echo "=== Manual Offline Cache Setup ===" >&2
      
      # Set cache directory from bunDeps
      export BUN_INSTALL_CACHE_DIR=${diagnostics.bunDeps}
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"
      
      # Run cache diagnostics
      check-bun-cache
      
      echo "" >&2
      echo "Running bun install with offline cache..." >&2
    '';

    installPhase = ''
      runHook preInstall
      
      # Run bun install with offline flags
      # --prefer-offline: Use cache if available, but may still check registry
      # --frozen-lockfile: Don't update lockfile
      set +e
      bun install --prefer-offline --frozen-lockfile 2>&1 | tee install.log || true
      install_status=$?
      set -e
      
      echo "" >&2
      echo "=== Install Result ===" >&2
      
      # Analyze install log for network activity
      if grep -iE "(fetch|download|network|registry|http|https)" install.log | grep -vE "(cache|offline|local)" | head -5; then
        echo "⚠ Warning: Potential network activity detected in install log" >&2
        echo "  This may indicate Bun is still trying to reach the registry" >&2
      fi
      
      if [ $install_status -eq 0 ]; then
        echo "✓ bun install completed" >&2
      else
        echo "⚠ bun install exited with status $install_status" >&2
        echo "  This may be expected if network access is blocked" >&2
      fi
      
      # Verify node_modules was created
      if [ -d node_modules ]; then
        echo "✓ node_modules directory created" >&2
        node_count=$(find node_modules -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l || echo "0")
        echo "  Found $node_count top-level packages" >&2
      else
        echo "✗ node_modules directory not found" >&2
        if [ $install_status -ne 0 ]; then
          echo "  Install failed - this may be due to network restrictions" >&2
          echo "  Consider using vendored node_modules approach" >&2
        fi
        exit 1
      fi
      
      mkdir -p "$out"
      cp -R . "$out"
      runHook postInstall
    '';

    buildPhase = ''
      runHook preBuild
      
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"
      export PATH="$PWD/node_modules/.bin:$PATH"

      # Verify dependencies are installed
      if [ ! -d node_modules ]; then
        echo "Error: node_modules not found after install phase" >&2
        exit 1
      fi

      echo "Dependencies installed successfully from offline cache"
      
      # Build using Bun workspace scripts (ESM output)
      bun run build
      
      runHook postBuild
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
  
  # Diagnostic outputs
  # bun-deps: The offline cache derivation (for inspection)
  # Build with: nix build .#bun-deps
  # Inspect with: nix-store -qR $(nix-build --no-out-link .#bun-deps) | head -20
  bun-deps = diagnostics.bunDeps;
  
  # bun-deps-verify: Verification info about bunDeps derivation
  # Build with: nix build .#bun-deps-verify && cat result
  bun-deps-verify = bunDepsVerify;
  
  # node-tree: Main node tree build using bun2nix.mkBunDerivation
  # Build with: nix build .#node-tree
  node-tree = nodeTree;
  
  # node-tree-manual: Fallback implementation using manual cache setup
  # Use this if mkBunDerivation hook is not working correctly
  # Build with: nix build .#node-tree-manual
  # To switch to this strategy, set bunInstallStrategy = "manual-cache" in nix/percy-config.nix
  node-tree-manual = nodeTreeManual;
}

