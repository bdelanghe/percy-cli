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
          inherit (pkgs) stdenv gnused;
          node = pkgs.nodejs_20;
          version = "0.0.1";

          pkgTarget = {
            "x86_64-linux" = "node20-linux-x64";
            "aarch64-linux" = "node20-linux-arm64";
            "x86_64-darwin" = "node20-macos-x64";
            "aarch64-darwin" = "node20-macos-arm64";
          }.${system};

          offlineCache = offlineCacheFor pkgs;

          # Layer 1: patched source tree
          src-patched = stdenv.mkDerivation {
            pname = "percy-cli-src-patched";
            inherit version;
            src = ./.;
            nativeBuildInputs = [ gnused ];
            dontBuild = true;
            installPhase = ''
              mkdir -p $out
              cp -R . $out
              cd $out

              sed -i '/"type": "module",/d' package.json

              if ! grep -q '"name":' package.json; then
                {
                  echo '{'
                  echo '  "name": "percy-cli",'
                  tail -n +2 package.json
                } > package.json.tmp && mv package.json.tmp package.json
              fi

              find packages -name package.json \
                -not -path "*/dom/*" \
                -not -path "*/sdk-utils/*" \
                -exec sed -i '/"type": "module",/d' {} \;
            '';
          };

          # Layer 2: node tree build (mkYarnPackage)
          node-tree = pkgs.mkYarnPackage {
            pname = "percy-cli-node-tree";
            inherit version;
            src = src-patched;
            yarnLock = ./yarn.lock;
            offlineCache = offlineCache;

            # Optional: small sanity check
            preConfigure = ''
              echo "Using offline cache at: ${offlineCache}"
              if ! find "${offlineCache}" -name "*.tgz" | head -1 | grep -q .; then
                echo "ERROR: offline cache ${offlineCache} has no .tgz files" >&2
                exit 1
              fi
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

          # Layer 3: pkg-wrapped CLI binary
          percy-cli = stdenv.mkDerivation {
            pname = "percy-cli";
            inherit version;

            src = node-tree;
            sourceRoot = "libexec/percy-cli-node-tree";

            nativeBuildInputs = [
              node
              gnused
              pkgs.nodePackages.pkg
            ];

            NODE_ENV = "production";

            patchPhase = ''
              if [ -f packages/cli/dist/percy.js ]; then
                {
                  echo "import { cli } from '@percy/cli';"
                  cat packages/cli/dist/percy.js
                } > packages/cli/dist/percy.js.new
                mv packages/cli/dist/percy.js.new packages/cli/dist/percy.js
              fi

              if [ -f packages/cli/bin/run.cjs ] && \
                 ! grep -q 'process.env.NODE_ENV = "executable";' packages/cli/bin/run.cjs; then
                sed -i '1a process.env.NODE_ENV = "executable";' packages/cli/bin/run.cjs
              fi
            '';

            dontBuild = true;
            dontConfigure = true;

            installPhase = ''
              mkdir -p "$out/bin"
              export NODE_PATH="$PWD/node_modules:$NODE_PATH"

              pkg ./packages/cli/bin/run.cjs -t ${pkgTarget} -d

              for name in run-${pkgTarget} run-linux run-macos run; do
                if [ -f "$name" ]; then
                  mv "$name" "$out/bin/percy"
                  chmod +x "$out/bin/percy"
                  exit 0
                fi
              done

              echo "Error: pkg did not produce expected binary" >&2
              ls -la
              exit 1
            '';

            meta = {
              description = "Percy CLI packaged via pkg";
              mainProgram = "percy";
              license = pkgs.lib.licenses.mit;
            };
          };

        in {
          inherit src-patched node-tree percy-cli;
          default = percy-cli;
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
          node_tree = self.packages.${system}.node-tree;
          default = self.packages.${system}.percy-cli;
        } else {}
      );
    };
}
