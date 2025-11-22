# bun-diagnostics.nix
# Helper functions for diagnosing bun2nix offline cache issues

{ pkgs, bunNix }:

rec {
  # Fetch bunDeps manually to verify it's being built
  bunDeps = pkgs.bun2nix.fetchBunDeps {
    bunNix = bunNix;
  };

  # Diagnostic script to check cache setup
  checkCacheSetup = pkgs.writeShellScript "check-bun-cache" ''
    set -e
    
    echo "=== Bun Cache Diagnostics ===" >&2
    echo "" >&2
    
    # Check BUN_INSTALL_CACHE_DIR (use ${...:-} to handle unset variable)
    cache_dir="''${BUN_INSTALL_CACHE_DIR:-}"
    if [ -n "$cache_dir" ]; then
      echo "✓ BUN_INSTALL_CACHE_DIR is set: $cache_dir" >&2
      
      if [ -d "$cache_dir" ]; then
        echo "✓ Cache directory exists" >&2
        
        # Count files in cache
        cache_files=$(find "$cache_dir" -type f | wc -l)
        echo "  Cache contains $cache_files files" >&2
        
        # Check for expected Bun cache structure
        # Bun cache typically has structure like: registry.npmjs.org/package-name/version/
        if find "$cache_dir" -type d -name "registry.npmjs.org" | grep -q .; then
          echo "✓ Found registry.npmjs.org structure in cache" >&2
        else
          echo "⚠ Warning: registry.npmjs.org structure not found in cache" >&2
        fi
        
        # List first few cache entries
        echo "" >&2
        echo "First 10 cache entries:" >&2
        find "$cache_dir" -type f | head -10 | sed 's/^/  /' >&2
      else
        echo "✗ Cache directory does not exist: $cache_dir" >&2
        exit 1
      fi
    else
      echo "✗ BUN_INSTALL_CACHE_DIR is not set" >&2
      exit 1
    fi
    
    echo "" >&2
    echo "=== End Diagnostics ===" >&2
  '';

  # Test derivation that manually sets up cache and runs bun install
  # This helps isolate whether the issue is in bun2nix hook or Bun itself
  testManualCache = { src, bunDeps }:
    pkgs.stdenv.mkDerivation {
      pname = "bun-cache-test";
      version = "1.0.0";
      inherit src;

      nativeBuildInputs = [
        pkgs.bun
        checkCacheSetup
      ];

      # Manually set up cache like bun2nix hook should do
      preInstall = ''
        echo "=== Manual Cache Setup Test ===" >&2
        
        # Set cache directory
        export BUN_INSTALL_CACHE_DIR=${bunDeps}
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        
        # Run diagnostics
        check-bun-cache
        
        echo "" >&2
        echo "Running bun install with --prefer-offline..." >&2
      '';

      installPhase = ''
        # Try bun install with offline flags
        # Capture output to see if it tries to hit network
        set +e
        bun install --prefer-offline --frozen-lockfile 2>&1 | tee install.log
        install_status=$?
        set -e
        
        echo "" >&2
        echo "=== Install Log Analysis ===" >&2
        
        # Check for network-related errors or attempts
        if grep -i "fetch\|download\|network\|registry\|http" install.log | grep -v "cache\|offline" | head -5; then
          echo "⚠ Warning: Found potential network activity in install log" >&2
        else
          echo "✓ No obvious network activity detected" >&2
        fi
        
        if [ $install_status -eq 0 ]; then
          echo "✓ bun install completed successfully" >&2
        else
          echo "✗ bun install failed with status $install_status" >&2
          echo "Full log:" >&2
          cat install.log >&2
          exit $install_status
        fi
        
        # Verify node_modules was created
        if [ -d node_modules ]; then
          echo "✓ node_modules directory created" >&2
          node_count=$(find node_modules -mindepth 1 -maxdepth 1 -type d | wc -l)
          echo "  Found $node_count top-level packages" >&2
        else
          echo "✗ node_modules directory not found" >&2
          exit 1
        fi
        
        mkdir -p "$out"
        cp -R . "$out"
      '';
    };
}

