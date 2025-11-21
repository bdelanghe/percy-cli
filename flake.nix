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
          yarnDeps = pkgs.fetchYarnDeps {
            yarnLock = ./yarn.lock;
            sha256 = pkgs.lib.fakeSha256; # Will be replaced with actual hash on first run
          };

          # Layer 2: node tree build (mkYarnPackage)
          nodeTree = pkgs.mkYarnPackage {
            pname = "percy-cli-node-tree";
            inherit (cfg) version;
            src = srcPatched;
            yarnLock = ./yarn.lock;
            offlineCache = yarnDeps;

            # Make sure devDependencies (including lerna) are installed
            NODE_ENV = "development";

            buildPhase = ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"

              export npm_config_offline=true
              export NPM_CONFIG_OFFLINE=true

              # Use the package.json script: "build": "lerna run build --stream"
              yarn run build

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