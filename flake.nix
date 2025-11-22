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
          offlineCacheFiles = import ./nix/offline-cache.nix { 
            inherit (pkgs) fetchurl fetchgit linkFarm runCommand gnutar;
          };

          # Layer 2: node tree build using Bun
          # Bun provides fast, reproducible builds with native workspace support
          nodeTree = pkgs.stdenv.mkDerivation {
            name = "percy-cli-node-tree";
            src = srcPatched;
            
            nativeBuildInputs = with pkgs; [
              bun
              nodejs
            ];
            
            # Make offline cache available as build input
            offlineCache = offlineCacheFiles.offline_cache;
            
            # Build phase - use Bun for install and build with offline cache
            buildPhase = ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"

              # Populate Bun's install cache with offline packages
              BUN_CACHE="$HOME/.bun/install/cache"
              mkdir -p "$BUN_CACHE"
              
              # Copy offline cache to Bun's cache directory
              # Bun will use these files if they match what it needs
              echo "Setting up offline cache for Bun..."
              cp -r ${offlineCacheFiles.offline_cache}/* "$BUN_CACHE/" 2>/dev/null || true
              
              # Configure Bun for offline installation
              export BUN_INSTALL_OFFLINE=1

              # Install dependencies with Bun using offline cache
              echo "Installing dependencies from offline cache..."
              bun install --frozen-lockfile --no-save || bun install --no-save

              # Add node_modules/.bin to PATH for build tools
              export PATH="$PWD/node_modules/.bin:$PATH"

              # Build all packages using Bun's workspace support
              bun run build

              # Build CJS versions if needed (Bun handles transpilation)
              bun run build_cjs || true
              if [ -d build ]; then
                cp -R build/* packages/
              fi
            '';
            
            installPhase = ''
              mkdir -p $out
              cp -R . $out
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