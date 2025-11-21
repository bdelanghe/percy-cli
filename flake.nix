{
  description = "Percy CLI binary built with pkg via Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-schemas.url = "github:DeterminateSystems/flake-schemas";
  };

  outputs = { self, nixpkgs, flake-schemas }:
    let
      systems = [
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-linux"
        "x86_64-darwin"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        f pkgs system);

    in {
      schemas = flake-schemas.schemas;

      packages = forAllSystems (pkgs: system:
        let
          cfg        = import ./nix/percy-config.nix { inherit pkgs; };
          srcPatched = import ./nix/src-patched.nix { inherit pkgs; version = cfg.version; };

          # Let Nix compute the offline cache from yarn.lock
          # Cache includes @nx/nx-darwin-arm64 that was added to yarn.lock
          yarnDeps = pkgs.fetchYarnDeps {
            yarnLock = ./yarn.lock;
            sha256 = "sha256-5ouUohCpHMXz9Xn9jWbNZ5QGe4xVZiFx4AzIEN9QYiQ=";
          };

          # Layer 2: node tree build (mkYarnPackage)
          nodeTree = pkgs.mkYarnPackage {
            pname = "percy-cli-node-tree";
            inherit (cfg) version;
            src = srcPatched;
            yarnLock = ./yarn.lock;
            offlineCache = yarnDeps;

            # Keep NODE_ENV=development to ensure build tools (babel, rollup) 
            # from devDependencies are available and behave correctly during build
            NODE_ENV = "development";


            buildPhase = ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"

              export npm_config_offline=true
              export NPM_CONFIG_OFFLINE=true
              # Suppress npm deprecation warnings
              export npm_config_loglevel=error

              # mkYarnPackage should have installed dependencies in configurePhase
              # Check if lerna is available - if not, mkYarnPackage might have installed with --production
              # In that case, we need to install devDependencies, but the offline cache should already be set up
              if [ ! -f node_modules/.bin/lerna ]; then
                echo "lerna not found, checking if devDependencies need to be installed..." >&2
                echo "Current directory: $PWD" >&2
                if [ -f package.json ]; then
                  echo "package.json found, installing devDependencies..." >&2
                  # mkYarnPackage sets up yarn's offline cache via yarnConfigHook
                  # We can use yarn install with --offline, but need to ensure the cache is available
                  # The cache from fetchYarnDeps should be linked by mkYarnPackage
                  yarn install --offline --frozen-lockfile --production=false --ignore-scripts 2>&1 || {
                    echo "ERROR: Failed to install devDependencies" >&2
                    echo "This might indicate the offline cache is not properly configured." >&2
                    echo "Checking yarn cache configuration..." >&2
                    yarn config get yarn-offline-mirror 2>&1 || true
                    exit 1
                  }
                else
                  echo "ERROR: package.json not found in $PWD" >&2
                  echo "Directory contents:" >&2
                  ls -la 2>&1 | head -20
                  exit 1
                fi
              fi

              # Add node_modules/.bin to PATH for babel, lerna, and other build tools
              export PATH="$PWD/node_modules/.bin:$PATH"

              # Enhanced diagnostic: Comprehensive check for devDependency binaries and Nx native modules
              echo "=== Diagnostic: Checking devDependency binaries and Nx native modules ===" >&2
              echo "NODE_ENV is set to: $NODE_ENV" >&2
              echo "System architecture: $(uname -m)" >&2
              echo "Platform: $(uname -s)" >&2
              echo "" >&2
              
              # Check if node_modules/.bin exists and list all binaries
              if [ -d node_modules/.bin ]; then
                echo "✓ node_modules/.bin exists" >&2
                echo "" >&2
                echo "All binaries in node_modules/.bin:" >&2
                ls -1 node_modules/.bin/ | sort >&2
                echo "" >&2
                
                # Count total binaries
                bin_count=$(ls -1 node_modules/.bin/ 2>/dev/null | wc -l | tr -d ' ')
                echo "Total binaries found: $bin_count" >&2
                echo "" >&2
              else
                echo "✗ ERROR: node_modules/.bin does not exist!" >&2
                echo "This suggests dependencies were not installed." >&2
                exit 1
              fi
              
              # Check for expected devDependency binaries
              echo "Checking for expected devDependency binaries:" >&2
              missing_bins=""
              lerna_missing=0
              
              for bin in babel eslint lerna karma nyc rollup tsd; do
                if [ -f "node_modules/.bin/$bin" ]; then
                  # Check if it's executable
                  if [ -x "node_modules/.bin/$bin" ]; then
                    echo "  ✓ $bin found and executable" >&2
                  else
                    echo "  ⚠ $bin found but NOT executable" >&2
                    missing_bins="$missing_bins $bin"
                    if [ "$bin" = "lerna" ]; then
                      lerna_missing=1
                    fi
                  fi
                elif command -v "$bin" >/dev/null 2>&1; then
                  echo "  ✓ $bin found in PATH (but not in node_modules/.bin)" >&2
                else
                  echo "  ✗ $bin NOT found" >&2
                  missing_bins="$missing_bins $bin"
                  if [ "$bin" = "lerna" ]; then
                    lerna_missing=1
                  fi
                fi
              done
              echo "" >&2
              
              # Special check for lerna and its Nx dependencies
              echo "=== Lerna and Nx Native Module Diagnostics ===" >&2
              
              # Check if lerna package exists
              if [ -d "node_modules/lerna" ]; then
                echo "✓ node_modules/lerna directory exists" >&2
                if [ -f "node_modules/lerna/package.json" ]; then
                  lerna_version=$(grep -o '"version": "[^"]*"' node_modules/lerna/package.json | cut -d'"' -f4 || echo "unknown")
                  echo "  Lerna version: $lerna_version" >&2
                fi
              else
                echo "✗ node_modules/lerna directory does NOT exist" >&2
                missing_bins="$missing_bins lerna"
                lerna_missing=1
              fi
              echo "" >&2
              
              # Check for @nx/nx-darwin-arm64 (critical for macOS ARM)
              if [ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ]; then
                echo "Checking for @nx/nx-darwin-arm64 (required for macOS ARM):" >&2
                if [ -d "node_modules/@nx/nx-darwin-arm64" ]; then
                  echo "  ✓ node_modules/@nx/nx-darwin-arm64 exists" >&2
                  if [ -f "node_modules/@nx/nx-darwin-arm64/package.json" ]; then
                    nx_version=$(grep -o '"version": "[^"]*"' node_modules/@nx/nx-darwin-arm64/package.json | cut -d'"' -f4 || echo "unknown")
                    echo "  @nx/nx-darwin-arm64 version: $nx_version" >&2
                  fi
                else
                  echo "  ✗ node_modules/@nx/nx-darwin-arm64 does NOT exist" >&2
                  echo "" >&2
                  echo "  ⚠ CRITICAL: This is the known Nx native module issue on macOS ARM!" >&2
                  echo "  The lerna postinstall script expects @nx/nx-darwin-arm64 to be present." >&2
                  echo "  Check if:" >&2
                  echo "    1. @nx/nx-darwin-arm64 is in package.json devDependencies (it should be)" >&2
                  echo "    2. The offline cache includes @nx/nx-darwin-arm64" >&2
                  echo "    3. yarn install --offline is actually installing devDependencies" >&2
                  echo "" >&2
                  # Check if @nx directory exists at all
                  if [ -d "node_modules/@nx" ]; then
                    echo "  Other @nx packages found:" >&2
                    ls -1 node_modules/@nx/ 2>/dev/null | head -10 >&2
                  else
                    echo "  ✗ node_modules/@nx directory does NOT exist" >&2
                  fi
                fi
                echo "" >&2
              fi
              
              # Check for other @nx packages that might be present
              if [ -d "node_modules/@nx" ]; then
                echo "All @nx packages installed:" >&2
                ls -1 node_modules/@nx/ 2>/dev/null >&2
                echo "" >&2
              fi
              
              # Check if lerna binary exists and try to get its version (this will fail if @nx/nx-darwin-arm64 is missing)
              if [ -f "node_modules/.bin/lerna" ]; then
                echo "Attempting to get lerna version (may fail if @nx/nx-darwin-arm64 is missing):" >&2
                if node_modules/.bin/lerna --version 2>&1; then
                  echo "  ✓ lerna command works" >&2
                else
                  echo "  ✗ lerna command failed (likely due to missing @nx/nx-darwin-arm64)" >&2
                fi
                echo "" >&2
              fi
              
              # Summary and exit if critical binaries are missing
              echo "=== Diagnostic Summary ===" >&2
              if [ -n "$missing_bins" ]; then
                echo "✗ Missing critical binaries:$missing_bins" >&2
                if [ "$lerna_missing" = "1" ]; then
                  echo "" >&2
                  echo "ERROR: lerna is missing or not executable!" >&2
                  echo "This will prevent the build from proceeding." >&2
                  exit 1
                fi
              else
                echo "✓ All expected binaries are present" >&2
              fi
              echo "=== End diagnostic ===" >&2
              echo "" >&2

              # Verify lerna is available and executable before proceeding
              if ! command -v lerna >/dev/null 2>&1; then
                echo "ERROR: lerna command not found in PATH" >&2
                echo "Even though diagnostics passed, lerna is not available for execution." >&2
                exit 1
              fi
              
              # Test lerna execution (will fail if @nx/nx-darwin-arm64 is missing)
              if ! lerna --version >/dev/null 2>&1; then
                echo "ERROR: lerna command found but execution failed!" >&2
                echo "This is likely due to missing @nx/nx-darwin-arm64 native module." >&2
                echo "Attempting to show the actual error:" >&2
                lerna --version 2>&1 || true
                exit 1
              fi

              # Run lerna build directly (using lerna from node_modules)
              lerna run build --stream

              # Run babel build_cjs directly
              BABEL_ENV=dev babel packages -d build || true
              if [ -d build ]; then
                cp -R build/* packages/
              fi
            '';
          };

          # Layer 3: prepared CLI tree (patched for pkg)
          preparedCli = import ./nix/prepared-cli.nix {
            inherit pkgs;
            nodeTree = nodeTree;
            version = cfg.version;
          };

          pkgWrapper = import ./nix/pkg-wrapper.nix { inherit pkgs; };

          # Layer 4: pkg-wrapped CLI binary
          percyCli = pkgWrapper {
            pname = "percy-cli";
            version = cfg.version;
            pkgTarget = cfg.pkgTargetFor system;
            preparedCli = preparedCli;
            entrypoint = "./packages/cli/bin/run.cjs";
            binaryName = "percy";
          };

        in {
          src-patched   = srcPatched;
          node-tree     = nodeTree;
          prepared-cli  = preparedCli;
          percy-cli     = percyCli;
          default       = percyCli;
        });

      apps = forAllSystems (pkgs: system: {
        percy-cli = {
          type = "app";
          program = "${self.packages.${system}.percy-cli}/bin/percy";
          meta.description = "Percy CLI executable";
        };
      });

      devShells = forAllSystems (pkgs: system: {
        default = import ./nix/dev-shell.nix { inherit pkgs; };
      });

      checks = forAllSystems (pkgs: system:
        if pkgs.stdenv.isDarwin then {
          src_patched = self.packages.${system}.src-patched;
          node_tree   = self.packages.${system}.node-tree;
          default     = self.packages.${system}.percy-cli;
        } else {}
      );
    };
}