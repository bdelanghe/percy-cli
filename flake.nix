{
  description = "Percy CLI binary built with pkg via Nix";

  inputs = {
    nixpkgs.url       = "github:NixOS/nixpkgs/nixos-24.05";
    flake-schemas.url = "github:DeterminateSystems/flake-schemas";
    bun2nix.url       = "github:nix-community/bun2nix";
    bun2nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, flake-schemas, bun2nix }:
    let
      systems = [
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-linux"
        "x86_64-darwin"
      ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system:
          let
            # Apply bun2nix overlay to pkgs for easier access to bun2nix functions
            pkgs = import nixpkgs {
              inherit system;
              overlays = [ bun2nix.overlays.default ];
            };
          in
          f pkgs system);

      # Build graph for each system (src → nodeTree → preparedCli → percyCli)
      perSystemPackages = forAllSystems (pkgs: system:
        let
          cfg = import ./nix/percy-config.nix { inherit pkgs; };

          srcPatched = import ./nix/src-patched.nix {
            inherit pkgs;
            version = cfg.version;
          };

          # Ensure bun.lock + bun.nix are present in src
          # These should be generated outside Nix and committed to version control
          hasBunLock = builtins.pathExists "${srcPatched}/bun.lock";
          hasBunNix  = builtins.pathExists "${srcPatched}/bun.nix";

          _ = if !hasBunLock || !hasBunNix then
            throw ''

              Missing Bun lock artifacts in src:

                bun.lock present: ${toString hasBunLock}
                bun.nix present:  ${toString hasBunNix}

              To fix:
                bun install
                bunx bun2nix -o bun.nix
                git add bun.lock bun.nix

            ''
          else
            null;

          # Offline Bun deps from committed bun.nix
          bunDeps = pkgs.bun2nix.fetchBunDeps {
            bunNix = "${srcPatched}/bun.nix";
          };

          # Layer 2: node tree build using bun2nix
          nodeTree = pkgs.stdenv.mkDerivation {
            pname   = "percy-cli-node-tree";
            version = cfg.version;
            src     = srcPatched;

            nativeBuildInputs = with pkgs; [
              bun
              nodejs
              pkgs.bun2nix.hook  # from overlay
            ];

            inherit bunDeps;

            buildPhase = ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"

              echo "Installing dependencies from bun2nix cache..."
              bun install --frozen-lockfile --no-save

              export PATH="$PWD/node_modules/.bin:$PATH"

              # Prefer Bun workspace scripts; fall back to Lerna if present
              bun run build || lerna run build --stream

              # Build CJS output (via babel or existing script)
              BABEL_ENV=dev babel packages -d build || true

              if [ -d build ]; then
                cp -R build/* packages/
              fi
            '';

            installPhase = ''
              mkdir -p "$out"
              cp -R . "$out"
            '';
          };

          # Layer 3: prepared CLI tree (patched for pkg)
          preparedCli = import ./nix/prepared-cli.nix {
            inherit pkgs nodeTree;
            version = cfg.version;
          };

          pkgWrapper = import ./nix/pkg-wrapper.nix { inherit pkgs; };

          # Layer 4: pkg-wrapped CLI binary
          percyCli = pkgWrapper {
            pname       = "percy-cli";
            version     = cfg.version;
            pkgTarget   = cfg.pkgTargetFor system;
            preparedCli = preparedCli;
            entrypoint  = "./packages/cli/bin/run.cjs";
            binaryName  = "percy";
          };

        in {
          src-patched  = srcPatched;
          node-tree    = nodeTree;
          prepared-cli = preparedCli;
          percy-cli    = percyCli;
          default      = percyCli;
        });

    in {
      schemas = flake-schemas.schemas;

      packages = perSystemPackages;

      apps = forAllSystems (pkgs: system: {
        percy-cli = {
          type = "app";
          program = "${perSystemPackages.${system}.percy-cli}/bin/percy";
          meta.description = "Percy CLI executable";
        };
      });

      devShells = forAllSystems (pkgs: system: {
        default = import ./nix/dev-shell.nix { inherit pkgs; };
      });

      checks = forAllSystems (pkgs: system:
        let
          p = perSystemPackages.${system};
          percyCli = p.percy-cli;
        in {
          # Build graph checks
          src_patched  = p."src-patched";
          node_tree    = p."node-tree";
          prepared_cli = p."prepared-cli";

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
            touch "$out"
          '';

          binary_smoke_test = pkgs.runCommand "percy-binary-smoke-test" {
            nativeBuildInputs = [ percyCli ];
          } ''
            if ${percyCli}/bin/percy --version >/dev/null 2>&1 || \
               ${percyCli}/bin/percy --help    >/dev/null 2>&1; then
              echo "✓ Binary runs successfully"
            else
              echo "ERROR: Binary failed to run"
              exit 1
            fi
            touch "$out"
          '';

          default = percyCli;
        }
      );
    };
}
