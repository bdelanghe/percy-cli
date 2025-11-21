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

      # Global: import offline cache once per pkgs
      offlineCacheFor = pkgs:
        (import ./nix/offline-cache.nix {
          inherit (pkgs) fetchurl fetchgit linkFarm runCommand gnutar;
        }).offline_cache;

    in {
      schemas = flake-schemas.schemas;

      packages = forAllSystems (pkgs: system:
        let
          cfg        = import ./nix/percy-config.nix { inherit pkgs; };
          srcPatched = import ./nix/src-patched.nix { inherit pkgs; version = cfg.version; };
          offline    = offlineCacheFor pkgs;

          # Layer 2: node tree build (mkYarnPackage)
          nodeTree = pkgs.mkYarnPackage {
            pname = "percy-cli-node-tree";
            inherit (cfg) version;
            src = srcPatched;
            yarnLock = ./yarn.lock;
            offlineCache = offline;

            # Optional: small sanity check
            preConfigure = ''
              echo "Using offline cache at: ${offline}"
              if [ ! -d "${offline}" ]; then
                echo "ERROR: offline cache directory ${offline} does not exist" >&2
                exit 1
              fi
              # Check for entries (files or symlinks) with .tgz in their names
              # linkFarm creates symlinks, so we check the symlink names directly
              # Use a loop to check if any entry matches the pattern
              found=0
              for entry in "${offline}"/*; do
                if [ -e "$entry" ] && [[ "$(basename "$entry")" == *.tgz ]]; then
                  found=1
                  break
                fi
              done
              if [ "$found" -eq 0 ]; then
                echo "ERROR: offline cache ${offline} has no .tgz entries" >&2
                echo "Cache directory contents:" >&2
                ls -la "${offline}" || true
                exit 1
              fi
              echo "Offline cache validation passed"
            '';

            buildPhase = ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"

              export npm_config_offline=true
              export NPM_CONFIG_OFFLINE=true

              # Use yarn to run lerna from node_modules (installed via yarn) instead of nixpkgs
              # This ensures we use the correct version (6.0.1) that matches package.json
              # yarn will use the local node_modules/.bin/lerna, avoiding any nixpkgs version
              if [ ! -f node_modules/.bin/lerna ]; then
                echo "Error: lerna not found in node_modules/.bin" >&2
                echo "Available binaries:" >&2
                ls -la node_modules/.bin/ || true
                exit 1
              fi

              # Ensure we use local lerna, not any system/nixpkgs version
              export PATH="$PWD/node_modules/.bin:$PATH"
              yarn lerna run build --stream

              npm run build_cjs || true
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
        default = import ./nix/percy-firefox.nix { inherit pkgs; };
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
