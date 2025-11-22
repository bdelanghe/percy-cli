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
          yarnDeps = pkgs.fetchYarnDeps {
            yarnLock = ./yarn.lock;
            sha256 = "sha256-5ouUohCpHMXz9Xn9jWbNZ5QGe4xVZiFx4AzIEN9QYiQ=";
          };

          # Layer 2: node tree build (mkYarnPackage)
          nodeTree = pkgs.mkYarnPackage {
            pname = "percy-cli-node-tree";
            inherit (cfg) version;
            src = srcPatched;
            yarnLock = ./yarn.lock;
            offlineCache = yarnDeps;

            # Add lerna from Nix packages to nativeBuildInputs
            # This provides lerna without needing to install devDependencies via yarn
            nativeBuildInputs = [ pkgs.nodePackages.lerna ];

            # Keep NODE_ENV=development to ensure build tools (babel, rollup) 
            # from devDependencies are available and behave correctly during build
            NODE_ENV = "development";

            buildPhase = ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"

              export npm_config_offline=true
              export NPM_CONFIG_OFFLINE=true
              # Suppress npm deprecation warnings
              export npm_config_loglevel=error

              # Add node_modules/.bin to PATH for babel and other build tools
              # mkYarnPackage structures things: source is in deps/percy-cli/
              # lerna is provided via nativeBuildInputs (Nix package)
              export PATH="$PWD/deps/percy-cli/node_modules/.bin:$PWD/node_modules/.bin:$PATH"

              # Verify lerna is available (from nativeBuildInputs)
              if ! command -v lerna >/dev/null 2>&1; then
                echo "ERROR: lerna command not found" >&2
                echo "lerna should be available via nativeBuildInputs." >&2
                exit 1
              fi

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
        if pkgs.stdenv.isDarwin then {
          src_patched = self.packages.${system}.src-patched;
          node_tree   = self.packages.${system}.node-tree;
          default     = self.packages.${system}.percy-cli;
        } else {}
      );
    };
}