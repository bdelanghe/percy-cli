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
          # Use mkYarnPackage with the existing offline cache for reliable, reproducible builds
          # mkYarnPackage includes devDependencies by default when they're in yarn.lock
          offlineCache = import ./nix/offline-cache.nix { inherit (pkgs) fetchurl fetchgit linkFarm runCommand gnutar; };
          
          nodeTree = pkgs.mkYarnPackage {
            name = "percy-cli-node-tree";
            src = srcPatched;
            yarnLock = "${srcPatched}/yarn.lock";
            packageJson = "${srcPatched}/package.json";
            yarnOfflineCache = offlineCache;
            
            # Build phase - run lerna and babel
            # Note: mkYarnPackage installs all dependencies including devDependencies
            buildPhase = ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"

              # Add node_modules/.bin to PATH for build tools
              export PATH="$PWD/node_modules/.bin:$PATH"

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