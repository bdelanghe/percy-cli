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
          # Regenerating hash after yarn.lock update
          yarnDeps = pkgs.fetchYarnDeps {
            yarnLock = ./yarn.lock;
            sha256 = pkgs.lib.fakeSha256;  # Will be replaced with actual hash
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

            # Override configurePhase to ensure devDependencies are installed
            # mkYarnPackage might install with --production by default
            configurePhase = ''
              runHook preConfigure
              
              # mkYarnPackage's default configurePhase runs yarn install,
              # but we need to ensure devDependencies are included
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"
              
              # Verify yarn.lock is in sync with package.json
              # This catches cases where package.json was modified but yarn install wasn't run
              echo "=== Verifying yarn.lock is in sync with package.json ===" >&2
              
              # Check for critical dependencies that must be in yarn.lock
              # If package.json has @nx/nx-darwin-arm64 but yarn.lock doesn't, 
              # fetchYarnDeps won't include it in the offline cache
              if grep -q '"@nx/nx-darwin-arm64"' package.json; then
                if ! grep -q '@nx/nx-darwin-arm64' yarn.lock; then
                  echo "ERROR: @nx/nx-darwin-arm64 is in package.json but NOT in yarn.lock!" >&2
                  echo "" >&2
                  echo "This means yarn.lock is out of sync with package.json." >&2
                  echo "Run 'yarn install' to update yarn.lock, then commit the updated yarn.lock." >&2
                  echo "" >&2
                  echo "Why this matters:" >&2
                  echo "  - fetchYarnDeps reads from yarn.lock, not package.json" >&2
                  echo "  - If a dependency isn't in yarn.lock, it won't be in the offline cache" >&2
                  echo "  - The build will fail when trying to install missing dependencies" >&2
                  exit 1
                else
                  echo "✓ @nx/nx-darwin-arm64 found in yarn.lock" >&2
                fi
              fi
              
              # Check for lerna in yarn.lock (should always be present)
              if grep -q '"lerna"' package.json; then
                if ! grep -q '"lerna@' yarn.lock; then
                  echo "ERROR: lerna is in package.json but NOT in yarn.lock!" >&2
                  echo "Run 'yarn install' to update yarn.lock" >&2
                  exit 1
                else
                  echo "✓ lerna found in yarn.lock" >&2
                fi
              fi
              
              echo "=== yarn.lock verification complete ===" >&2
              echo "" >&2
              
              # Install all dependencies including devDependencies
              yarn install --offline --frozen-lockfile --production=false
              
              runHook postConfigure
            '';

            buildPhase = ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"

              export npm_config_offline=true
              export NPM_CONFIG_OFFLINE=true
              # Suppress npm deprecation warnings
              export npm_config_loglevel=error

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