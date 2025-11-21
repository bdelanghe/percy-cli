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

      # Helper: give each system both pkgs and system
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        f pkgs system);

    in {
      # Flake schemas for better tooling support and validation
      schemas = flake-schemas.schemas;

      packages = forAllSystems (pkgs: system:
        let
          inherit (pkgs) stdenv yarn gnused;
          node = pkgs.nodejs_20;
          version = "0.0.1";

          # Map Nix system to pkg target
          pkgTarget = {
            "x86_64-linux" = "node20-linux-x64";
            "aarch64-linux" = "node20-linux-arm64";
            "x86_64-darwin" = "node20-macos-x64";
            "aarch64-darwin" = "node20-macos-arm64";
          }.${system};

          # Layer 1: Patched source derivation
          # Removes "type": "module" early so all consumers see consistent CJS semantics
          # This is arch-agnostic and cache-friendly
          patchedSrc = stdenv.mkDerivation {
            pname = "percy-cli-src-patched";
            inherit version;
            src = ./.;
            nativeBuildInputs = [ gnused ];
            dontBuild = true;
            installPhase = ''
              mkdir -p $out
              cp -R . $out
              cd $out
              
              # Remove "type": "module" from root package.json
              sed -i '/"type": "module",/d' package.json
              
              # Add name field to root package.json for mkYarnPackage compatibility
              # (mkYarnPackage expects a name field for metadata extraction)
              if ! grep -q '"name":' package.json; then
                # Insert name field after opening brace using a temporary file
                {
                  echo '{'
                  echo '  "name": "percy-cli",'
                  tail -n +2 package.json
                } > package.json.tmp && mv package.json.tmp package.json
              fi
              
              # Remove from all package.json files except dom and sdk-utils
              find packages -name package.json \
                -not -path "*/dom/*" \
                -not -path "*/sdk-utils/*" \
                -exec sed -i '/"type": "module",/d' {} \;
            '';
          };

          # Prefetch yarn dependencies for offline cache
          # This creates a directory of .tgz tarballs that Yarn can use offline
          yarnDeps = pkgs.fetchYarnDeps {
            yarnLock = ./yarn.lock;
            hash = "sha256-WDkPwahNIcB50PAYiDX9CNGKNCU08sou8Y0d6qTrEyM=";
          };

          # Validation: Check that yarnDeps exists and contains expected packages
          # This will fail early if the offline cache is missing or incomplete
          # Run with: nix build .#packages.x86_64-darwin.yarnDepsCheck
          yarnDepsCheck = stdenv.mkDerivation {
            pname = "percy-cli-yarn-deps-check";
            inherit version;
            dontBuild = true;
            dontUnpack = true;
            installPhase = ''
              echo "Validating yarnDeps offline cache..."
              
              # Check that yarnDeps path exists
              if [ ! -d "${yarnDeps}" ]; then
                echo "ERROR: yarnDeps path does not exist: ${yarnDeps}" >&2
                exit 1
              fi
              
              # Check that it contains .tgz files (at least some packages)
              tgz_count=$(find "${yarnDeps}" -name "*.tgz" 2>/dev/null | wc -l | tr -d ' ')
              if [ "$tgz_count" -eq 0 ]; then
                echo "ERROR: yarnDeps cache contains no .tgz files" >&2
                echo "This means fetchYarnDeps did not download any packages." >&2
                echo "Possible causes:" >&2
                echo "  1. The hash in fetchYarnDeps is incorrect" >&2
                echo "  2. yarn.lock has changed but hash wasn't updated" >&2
                echo "  3. fetchYarnDeps failed to fetch packages" >&2
                exit 1
              fi
              
              echo "✓ yarnDeps cache validated: found $tgz_count .tgz files"
              echo "✓ Offline cache is ready for mkYarnPackage"
              
              # Create a marker file to indicate validation passed
              mkdir -p $out
              echo "yarnDeps validation passed" > $out/validation.txt
              echo "Cache location: ${yarnDeps}" >> $out/validation.txt
              echo "Package count: $tgz_count" >> $out/validation.txt
            '';
          };

          # Layer 2: Yarn build derivation (mkYarnPackage)
          # Builds JS project with patched source, producing a complete node tree
          # This is arch-agnostic (if no native addons) and highly cache-friendly
          # mkYarnPackage handles yarn2nix + offline cache internally
          # Explicitly pass yarnDeps as offlineCache - mkYarnPackage will handle the derivation
          nodeTree = pkgs.mkYarnPackage rec {
            pname = "percy-cli-node-tree";
            inherit version;
            src = patchedSrc;
            yarnLock = ./yarn.lock;
            # Pass yarnDeps derivation directly - mkYarnPackage will realize it
            offlineCache = yarnDeps;
            # Ensure yarnDeps is built by referencing it in buildInputs
            # This forces it to be built before mkYarnPackage tries to use it
            buildInputs = [ yarnDeps ];
            
            # Pre-configure validation: Verify offline cache is accessible
            # Using ${yarnDeps} in string interpolation ensures it's built as a dependency
            preConfigure = ''
              echo "Pre-configure check: Verifying offline cache..."
              
              # Reference yarnDeps directly to ensure it's built
              cache_path="${yarnDeps}"
              
              if [ -z "$cache_path" ] || [ ! -d "$cache_path" ]; then
                echo "ERROR: offlineCache (yarnDeps) is not accessible" >&2
                echo "Expected path: $cache_path" >&2
                echo "This will cause 'yarn install' to fail in offline mode." >&2
                ls -la "$(dirname "$cache_path")" 2>&1 || true
                exit 1
              fi
              
              # Check for at least some packages in the cache
              tgz_count=$(find "$cache_path" -name "*.tgz" 2>/dev/null | wc -l | tr -d ' ')
              if [ "$tgz_count" -eq 0 ]; then
                echo "ERROR: offlineCache appears empty (no .tgz files found)" >&2
                echo "Cache path: $cache_path" >&2
                echo "Directory contents:" >&2
                ls -la "$cache_path" 2>&1 | head -20 || true
                echo "This suggests fetchYarnDeps hash may be incorrect." >&2
                echo "Run: nix build .#packages.${system}.yarnDepsCheck to validate" >&2
                exit 1
              fi
              
              echo "✓ Offline cache verified: $cache_path (found $tgz_count .tgz files)"
            '';
            
            # mkYarnPackage installs production dependencies by default
            # We need devDependencies (like lerna) for the build
            # Install them after mkYarnPackage's configurePhase
            # mkYarnPackage's yarnConfigHook has configured yarn to use the offline cache
            postConfigure = ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"
              
              # mkYarnPackage's configurePhase has set up yarn to use the offline cache
              # Install devDependencies - MUST use --offline to prevent network access
              # This installs lerna and other devDependencies into node_modules/.bin
              yarn install --offline --frozen-lockfile --ignore-scripts
            '';
            
            # Build the project as part of mkYarnPackage
            buildPhase = ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"
              
              # Enforce offline for any npm/npx subprocesses
              export npm_config_offline=true
              export NPM_CONFIG_OFFLINE=true
              
              # Ensure local binaries (including lerna) are visible
              # lerna is installed as a devDependency via yarn install in postConfigure
              export PATH="$PWD/node_modules/.bin:$PATH"
              
              # Verify lerna is available (from node_modules/.bin, installed via yarn)
              if ! command -v lerna >/dev/null 2>&1; then
                echo "Error: lerna not found in node_modules/.bin" >&2
                echo "This means devDependencies weren't installed correctly." >&2
                echo "Checking node_modules/.bin:" >&2
                ls -la "$PWD/node_modules/.bin" 2>&1 || echo "node_modules/.bin does not exist" >&2
                exit 1
              fi
              
              # Monorepo build
              lerna run build --stream
              
              npm run build_cjs || true
              if [ -d build ]; then
                cp -R build/* packages/
              fi
            '';
          };

          # Layer 3: Binary packaging derivation
          # Takes built JS tree, applies CLI-specific patches, and wraps with pkg
          # This is per-system (pkg target varies by architecture)
          percy-cli = stdenv.mkDerivation {
            pname = "percy-cli";
            inherit version;

            src = nodeTree;
            # mkYarnPackage nests the project under libexec/<pname>
            sourceRoot = "libexec/percy-cli-node-tree";

            nativeBuildInputs = [
              node
              gnused
              pkgs.nodePackages.pkg
            ];

            NODE_ENV = "production";

            # CLI-specific patches: percy.js prepend and NODE_ENV injection
            patchPhase = ''
              # Prepend import to percy.js
              if [ -f packages/cli/dist/percy.js ]; then
                {
                  echo "import { cli } from '@percy/cli';"
                  cat packages/cli/dist/percy.js
                } > packages/cli/dist/percy.js.new
                mv packages/cli/dist/percy.js.new packages/cli/dist/percy.js
              fi

              # Ensure NODE_ENV is set in run.cjs
              if [ -f packages/cli/bin/run.cjs ] && \
                 ! grep -q 'process.env.NODE_ENV = "executable";' packages/cli/bin/run.cjs; then
                sed -i '1a process.env.NODE_ENV = "executable";' packages/cli/bin/run.cjs
              fi
            '';

            dontBuild = true;
            dontConfigure = true;

            installPhase = ''
              mkdir -p "$out/bin"

              # Ensure node_modules is accessible for pkg
              export NODE_PATH="$PWD/node_modules:$NODE_PATH"

              # Binary packaging logic (also available as scripts/percy-make-binary.sh for CI)
              # Use Nix-provided pkg instead of npx -y pkg for purity (no network access)
              pkg ./packages/cli/bin/run.cjs -t ${pkgTarget} -d

              # pkg can name outputs differently; handle the common cases
              for name in run-${pkgTarget} run-linux run-macos run; do
                if [ -f "$name" ]; then
                  mv "$name" "$out/bin/percy"
                  chmod +x "$out/bin/percy"
                  exit 0
                fi
              done

              echo "Error: pkg did not produce expected binary" >&2
              echo "Expected one of: run-${pkgTarget}, run-linux, run-macos, run" >&2
              ls -la
              exit 1
            '';

            meta = {
              description = "Percy CLI packaged via pkg";
              mainProgram = "percy";
              license = pkgs.lib.licenses.mit;
            };
          };

        in {
          inherit percy-cli;
          inherit yarnDepsCheck;
          default = percy-cli;
        });

      apps = forAllSystems (pkgs: system: {
        percy-cli = {
          type = "app";
          program = "${self.packages.${system}.percy-cli}/bin/percy";
          meta.description = "Percy CLI executable";
        };
      });

      devShells = forAllSystems (pkgs: system: {
        default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            nodejs_20
            yarn
            yarn2nix
            git
            zip
            gnused
          ];
        };
      });

      # Conditional checks: only define checks for systems that can be built locally
      # This allows `nix flake check` to work on darwin without requiring Linux builders
      # Linux packages remain defined for CI but aren't checked locally
      checks = forAllSystems (pkgs: system:
        if pkgs.stdenv.isDarwin then {
          # Validate offline cache before attempting full build
          yarn-deps-check = self.packages.${system}.yarnDepsCheck;
          # Full package build
          default = self.packages.${system}.percy-cli;
        } else {}
      );
    };
}