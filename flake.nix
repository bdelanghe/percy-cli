{
  description = "Percy CLI binary built with pkg via Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };

          # Using Node 20 since nodejs_14 is EOL and removed from nixpkgs
          node = pkgs.nodejs_20;
          yarn = pkgs.yarn;
          gsed = pkgs.gnused;

          # Map Nix system to pkg target
          pkgTarget = {
            "x86_64-linux" = "node20-linux-x64";
            "aarch64-linux" = "node20-linux-arm64";
            "x86_64-darwin" = "node20-macos-x64";
            "aarch64-darwin" = "node20-macos-arm64";
          }.${system};

        in rec {
          percy-cli = pkgs.stdenv.mkDerivation {
            pname = "percy-cli";
            version = "0.0.1";

            src = ./.;

            nativeBuildInputs = [ node yarn gsed ];

            NODE_ENV = "production";

            # Patch phase: remove "type": "module" from package.json files
            patchPhase = ''
              # Remove from root package.json
              gsed -i '/"type": "module",/d' package.json

              # Remove from all package.json files except dom and sdk-utils
              find packages -name package.json -not -path "*/dom/*" -not -path "*/sdk-utils/*" \
                -exec gsed -i '/"type": "module",/d' {} \;
            '';

            # Build phase: install, build, and transform
            buildPhase = ''
              export HOME=$TMPDIR/home
              mkdir -p $HOME

              yarn install --frozen-lockfile
              yarn build

              # Prepend import to percy.js using process substitution (no temp file)
              if [ -f packages/cli/dist/percy.js ]; then
                { echo "import { cli } from '@percy/cli';"; cat packages/cli/dist/percy.js; } > packages/cli/dist/percy.js.new
                mv packages/cli/dist/percy.js.new packages/cli/dist/percy.js
              fi

              # Ensure NODE_ENV is set in run.cjs
              if [ -f packages/cli/bin/run.cjs ] && ! grep -q 'process.env.NODE_ENV = "executable";' packages/cli/bin/run.cjs; then
                gsed -i '1a process.env.NODE_ENV = "executable";' packages/cli/bin/run.cjs
              fi

              npm run build_cjs
              [ -d build ] && cp -R build/* packages/
            '';

            # Install phase: package with pkg
            installPhase = ''
              mkdir -p $out/bin

              npx -y pkg ./packages/cli/bin/run.js -t ${pkgTarget} -d

              # Find the generated binary (pkg naming varies)
              for name in run-${pkgTarget} run-linux run-macos run; do
                if [ -f "$name" ]; then
                  mv "$name" $out/bin/percy
                  chmod +x $out/bin/percy
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

          default = percy-cli;
        });

      apps = forAllSystems (system: {
        percy-cli = {
          type = "app";
          program = "${self.packages.${system}.percy-cli}/bin/percy";
          meta.description = "Percy CLI executable";
        };
      });

      devShells = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; };
        in {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              nodejs_20 yarn git zip coreutils gnused
            ];
          };
        }
      );
    };
}
