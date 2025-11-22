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
          # Use dream2nix to build node_modules with all dependencies including devDependencies
          # According to dream2nix docs: https://dream2nix.dev/guides/getting-started/
          dream2nixEval = dream2nix.lib.evalModules {
            packageSets.nixpkgs = pkgs;
            modules = [
              {
                paths.projectRoot = srcPatched;
                paths.package = srcPatched;
                paths.packageJson = "${srcPatched}/package.json";
                paths.lockFile = "${srcPatched}/yarn.lock";
                name = "percy-cli";
                translator = "yarn-lock";
                subsystemInfo = {
                  nodejs = 20;
                };
                settings = {
                  includeDevDependencies = true;
                };
              }
            ];
          };

          # Extract node_modules from dream2nix build
          # The structure is: dream2nixEval.packages.<name>.public.nodeModules
          dream2nixPackage = dream2nixEval.packages."percy-cli";
          nodeModules = dream2nixPackage.public.nodeModules;

          # Build the complete node tree with source and dependencies
          nodeTree = pkgs.stdenv.mkDerivation {
            pname = "percy-cli-node-tree";
            inherit (cfg) version;
            
            src = srcPatched;
            
            nativeBuildInputs = with pkgs; [
              nodejs_20
            ];

            buildPhase = ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"

              # Copy source
              cp -R $src/* .
              chmod -R u+w .

              # Link node_modules from dream2nix
              ln -sfn ${nodeModules}/node_modules node_modules

              # Add node_modules/.bin to PATH for build tools
              export PATH="$PWD/node_modules/.bin:$PATH"

              # Diagnostic: Verify lerna is available
              echo "=== Checking lerna availability ===" >&2
              echo "Current directory: $PWD" >&2
              
              if [ ! -f node_modules/.bin/lerna ]; then
                echo "✗ ERROR: lerna not found in node_modules/.bin" >&2
                echo "Checking node_modules structure:" >&2
                if [ -d node_modules/.bin ]; then
                  echo "node_modules/.bin contents:" >&2
                  ls -1 node_modules/.bin/ 2>&1 | head -20 >&2
                else
                  echo "node_modules/.bin does not exist" >&2
                fi
                exit 1
              fi
              
              echo "✓ lerna found in node_modules/.bin" >&2
              
              # Verify lerna is executable
              if ! command -v lerna >/dev/null 2>&1; then
                echo "✗ ERROR: lerna not found in PATH" >&2
                echo "PATH includes: $PATH" >&2
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

            installPhase = ''
              mkdir -p $out
              # Copy everything except node_modules (which is a symlink)
              find . -mindepth 1 -maxdepth 1 ! -name node_modules -exec cp -R {} $out/ \;
              # Create node_modules symlink in output
              ln -sfn ${nodeModules}/node_modules $out/node_modules
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