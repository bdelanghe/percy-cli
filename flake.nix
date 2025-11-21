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
          # Using lib.fakeSha256 to force regeneration - Nix will calculate the correct hash
          yarnDeps = pkgs.fetchYarnDeps {
            yarnLock = ./yarn.lock;
            sha256 = pkgs.lib.fakeSha256;
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

              # Diagnostic: List all available binaries from devDependencies
              echo "=== Diagnostic: Checking devDependency binaries ===" >&2
              echo "NODE_ENV is set to: $NODE_ENV" >&2
              
              if [ -d node_modules/.bin ]; then
                echo "node_modules/.bin exists. Contents:" >&2
                ls -la node_modules/.bin/ >&2
                echo "" >&2
                echo "Expected devDependency binaries:" >&2
                echo "  - babel (from @babel/cli)" >&2
                echo "  - eslint (from eslint)" >&2
                echo "  - lerna (from lerna)" >&2
                echo "  - karma (from karma)" >&2
                echo "  - nyc (from nyc)" >&2
                echo "  - rollup (from rollup)" >&2
                echo "  - tsd (from tsd)" >&2
                echo "" >&2
                echo "Checking for specific binaries:" >&2
                for bin in babel eslint lerna karma nyc rollup tsd; do
                  if [ -f "node_modules/.bin/$bin" ] || command -v "$bin" >/dev/null 2>&1; then
                    echo "  ✓ $bin found" >&2
                  else
                    echo "  ✗ $bin NOT found" >&2
                  fi
                done
              else
                echo "ERROR: node_modules/.bin does not exist!" >&2
                echo "This suggests dependencies were not installed." >&2
              fi
              echo "=== End diagnostic ===" >&2
              echo "" >&2

              # Verify lerna is available
              if ! command -v lerna >/dev/null 2>&1; then
                echo "Error: lerna command not found" >&2
                echo "Checking if lerna package is installed:" >&2
                if [ -d "node_modules/lerna" ]; then
                  echo "  node_modules/lerna directory exists" >&2
                  ls -la node_modules/lerna/ 2>&1 | head -10 >&2
                else
                  echo "  node_modules/lerna directory does NOT exist" >&2
                fi
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