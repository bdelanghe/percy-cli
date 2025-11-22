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

          # Layer 2: node tree build using mkYarnPackage
          # Note: After attempting dream2nix integration, we're reverting to mkYarnPackage
          # as it's more straightforward for this use case. Dream2nix integration can be
          # revisited later with a better understanding of its API for accessing node_modules.
          
          # Let Nix compute the offline cache from yarn.lock
          yarnDeps = pkgs.fetchYarnDeps {
            yarnLock = ./yarn.lock;
            sha256 = "sha256-5ouUohCpHMXz9Xn9jWbNZ5QGe4xVZiFx4AzIEN9QYiQ=";
          };

          # Build node_modules using mkYarnPackage with devDependencies
          # The key is to ensure NODE_ENV=development and use the correct structure
          nodeTree = pkgs.mkYarnPackage {
            pname = "percy-cli-node-tree";
            inherit (cfg) version;
            src = srcPatched;
            yarnLock = ./yarn.lock;
            offlineCache = yarnDeps;

            # Keep NODE_ENV=development to ensure devDependencies are installed
            NODE_ENV = "development";

            buildPhase = ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"

              export npm_config_offline=true
              export NPM_CONFIG_OFFLINE=true
              export npm_config_loglevel=error

              # mkYarnPackage structures: source is in deps/percy-cli/
              # Add node_modules/.bin to PATH for build tools
              export PATH="$PWD/deps/percy-cli/node_modules/.bin:$PWD/node_modules/.bin:$PATH"

              # Diagnostic: Verify lerna is available
              echo "=== Checking lerna availability ===" >&2
              echo "Current directory: $PWD" >&2
              
              LERNA_FOUND=0
              if [ -f deps/percy-cli/node_modules/.bin/lerna ]; then
                echo "✓ lerna found in deps/percy-cli/node_modules/.bin" >&2
                LERNA_FOUND=1
              elif [ -f node_modules/.bin/lerna ]; then
                echo "✓ lerna found in node_modules/.bin" >&2
                LERNA_FOUND=1
              fi
              
              if [ "$LERNA_FOUND" = "0" ]; then
                echo "✗ ERROR: lerna not found in node_modules/.bin" >&2
                echo "This suggests devDependencies were not installed." >&2
                echo "Checking node_modules structure:" >&2
                if [ -d deps/percy-cli/node_modules/.bin ]; then
                  echo "deps/percy-cli/node_modules/.bin contents:" >&2
                  ls -1 deps/percy-cli/node_modules/.bin/ 2>&1 | head -20 >&2
                else
                  echo "deps/percy-cli/node_modules/.bin does not exist" >&2
                fi
                exit 1
              fi
              
              echo "✓ lerna is available and ready to use" >&2
              echo "" >&2

              # Run lerna build
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
        let
          percyCli = self.packages.${system}.percy-cli;
        in
        {
          # Build verification checks
          src_patched = self.packages.${system}.src-patched;
          node_tree = self.packages.${system}.node-tree;
          prepared_cli = self.packages.${system}.prepared-cli;
          
          # Binary existence and executability check
          binary_exists = pkgs.runCommand "percy-binary-exists-check" {} ''
            if [ ! -f ${percyCli}/bin/percy ]; then
              echo "ERROR: Binary not found at ${percyCli}/bin/percy"
              exit 1
            fi
            if [ ! -x ${percyCli}/bin/percy ]; then
              echo "ERROR: Binary is not executable"
              exit 1
            fi
            echo "✓ Binary exists and is executable"
            touch $out
          '';
          
          # Basic smoke test - check that binary runs (--version or --help)
          binary_smoke_test = pkgs.runCommand "percy-binary-smoke-test" {
            nativeBuildInputs = [ percyCli ];
          } ''
            # Try --version first, fall back to --help if that doesn't work
            if ${percyCli}/bin/percy --version >/dev/null 2>&1 || \
               ${percyCli}/bin/percy --help >/dev/null 2>&1; then
              echo "✓ Binary runs successfully"
            else
              echo "ERROR: Binary failed to run"
              exit 1
            fi
            touch $out
          '';
          
          # Default check (builds the full package)
          default = percyCli;
        }
      );
    };
}