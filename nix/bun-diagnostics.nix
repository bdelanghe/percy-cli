# bun-diagnostics.nix
# Helper functions for diagnosing bun2nix offline cache issues

{ pkgs, bunNix }:

rec {
  # Fetch bunDeps manually to verify it's being built
  bunDeps = pkgs.bun2nix.fetchBunDeps {
    bunNix = bunNix;
  };

  # Diagnostic script to check cache setup
  # Can optionally take cache dir as first argument, otherwise uses BUN_INSTALL_CACHE_DIR env var
  checkCacheSetup = pkgs.writeShellScript "check-bun-cache" ''
    set -e
    
    # Allow cache dir to be passed as first argument, or use env var
    if [ -n "$1" ]; then
      cache_dir="$1"
      echo "=== Bun Cache Diagnostics ===" >&2
      echo "Using cache directory from argument: $cache_dir" >&2
    else
      cache_dir="''${BUN_INSTALL_CACHE_DIR:-}"
      echo "=== Bun Cache Diagnostics ===" >&2
      echo "Using cache directory from BUN_INSTALL_CACHE_DIR env var: $cache_dir" >&2
    fi
    echo "" >&2
    
    # Use cache_dir from argument or environment variable
    if [ -n "$cache_dir" ]; then
      echo "✓ Cache directory: $cache_dir" >&2
      
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

  # Note: testManualCache was removed - it was experimental scaffolding that wasn't
  # properly wired. The proper solution is bun2nix.fetchBunDeps + bun2nix.hook
  # which is already implemented in the main nodeTree derivation.
}

