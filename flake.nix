{
  description = "Percy CLI binary built with pkg via Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-schemas.url = "github:DeterminateSystems/flake-schemas";
    dream2nix.url = "github:nix-community/dream2nix";
    dream2nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, flake-schemas, dream2nix }:
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

          # Layer 2: node tree build using dream2nix
          # Let dream2nix handle the entire Node.js build including devDependencies
          # This is cleaner than mkYarnPackage + manual build orchestration
          dream2nixLib = dream2nix.lib.${system};
          
          dream2nixPackage = dream2nixLib.evalModules {
            packageSets.nixpkgs = pkgs;
            modules = [
              # Pass module as a path, not an imported function
              ./nix/dream2nix-config.nix
              {
                paths.projectRoot = srcPatched;
                paths.package = srcPatched;
                paths.projectRootFile = "package.json";
                name = "percy-cli";
                # dream2nix will auto-detect translator from yarn.lock
              }
            ];
            # specialArgs provides extra arguments to all modules
            specialArgs = {
              inherit dream2nix srcPatched;
            };
          };

          # Extract the built package from dream2nix
          # dream2nix handles: node_modules install (with devDependencies) + lerna build + babel
          nodeTree = dream2nixPackage.packages."percy-cli" or dream2nixPackage;

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