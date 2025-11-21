{
  description = "Percy CLI binary built with pkg via Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      # Helper: give each system both pkgs and system
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        f pkgs system);

    in {
      packages = forAllSystems (pkgs: system:
        let
          inherit (pkgs) stdenv yarn gnused;
          node = pkgs.nodejs_20;

          # Map Nix system to pkg target
          pkgTarget = {
            "x86_64-linux" = "node20-linux-x64";
            "aarch64-linux" = "node20-linux-arm64";
            "x86_64-darwin" = "node20-macos-x64";
            "aarch64-darwin" = "node20-macos-arm64";
          }.${system};

          # Prefetched yarn dependencies (fixed-output derivation)
          yarnDeps = pkgs.fetchYarnDeps {
            yarnLock = ./yarn.lock;
            hash = "sha256-WDkPwahNIcB50PAYiDX9CNGKNCU08sou8Y0d6qTrEyM=";
          };

        in {
          percy-cli = stdenv.mkDerivation {
            pname = "percy-cli";
            version = "0.0.1";

            src = ./.;

            nativeBuildInputs = [
              node
              yarn
              gnused
            ];

            NODE_ENV = "production";

            patchPhase = ''
              # Remove "type": "module" from root package.json
              sed -i '/"type": "module",/d' package.json

              # Remove from all package.json files except dom and sdk-utils
              find packages -name package.json \
                -not -path "*/dom/*" \
                -not -path "*/sdk-utils/*" \
                -exec sed -i '/"type": "module",/d' {} \;
            '';

            buildPhase = ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"

              # Use prefetched yarn dependencies as cache
              export YARN_CACHE_FOLDER=${yarnDeps}

              # Offline/frozen as far as possible
              yarn install --frozen-lockfile --offline || yarn install --frozen-lockfile
              yarn build

              # Prepend import to percy.js
              if [ -f packages/cli/dist/percy.js ]; then
                {
                  echo "import { cli } from '@percy/cli';"
                  cat packages/cli/dist/percy.js
                } > packages/cli/dist/percy.js.new
                mv packages/cli/dist/percy.js.new packages/cli/dist/percy.js
              fi

              # Ensure NODE_ENV is set in run.cjs
              if [ -f packages/cli/bin/run.cjs ] && \
                 ! grep -q 'process.env.NODE_ENV = "executable";' packages/cli/bin/run.cjs; then
                sed -i '1a process.env.NODE_ENV = "executable";' packages/cli/bin/run.cjs
              fi

              npm run build_cjs
              if [ -d build ]; then
                cp -R build/* packages/
              fi
            '';

            installPhase = ''
              mkdir -p "$out/bin"

              npx -y pkg ./packages/cli/bin/run.js -t ${pkgTarget} -d

              # pkg can name outputs differently; handle the common cases
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
            };
          };

          default = self.packages.${system}.percy-cli;
        });

      apps = forAllSystems (pkgs: system: {
        percy-cli = {
          type = "app";
          program = "${self.packages.${system}.percy-cli}/bin/percy";
          meta.description = "Percy CLI executable";
        };
      });

      devShells = forAllSystems (pkgs: system: {
        default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nodejs_20
            yarn
            git
            zip
            coreutils
            gnused
          ];
        };
      });
    };
}
