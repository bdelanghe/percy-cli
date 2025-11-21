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

          node = pkgs.nodejs_14;
          yarn = pkgs.yarn;
          gsed = pkgs.gnused;
          zip = pkgs.zip;

          # Get pkg via npx (will be available in buildPhase)
          pkgNode = pkgs.nodePackages_latest.pkg;

          # Map Nix system to pkg target
          systemToPkgTarget = {
            "x86_64-linux" = "node14-linux-x64";
            "aarch64-linux" = "node14-linux-arm64";
            "x86_64-darwin" = "node14-macos-x64";
            "aarch64-darwin" = "node14-macos-arm64";
          };

          pkgTarget = systemToPkgTarget.${system};

        in {
          percy-cli = pkgs.stdenv.mkDerivation {
            pname = "percy-cli";
            version = "0.0.1"; # TODO: read from package.json

            src = ./.;

            nativeBuildInputs = [
              node
              yarn
              gsed
              zip
              pkgs.makeWrapper
            ];

            # Set environment variables
            NODE_ENV = "production";
            HOME = "$TMPDIR/home";

            # Patch phase: modify package.json files and source files
            patchPhase = ''
              # Create home directory for yarn
              mkdir -p "$HOME"

              # 1) Remove "type": "module" from root package.json
              ${gsed}/bin/gsed -i '/"type": "module",/d' package.json

              # 2) Remove "type": "module" from package.json files, except dom and sdk-utils
              for pkg_json in packages/*/package.json; do
                case "$pkg_json" in
                  ./packages/dom/package.json|./packages/sdk-utils/package.json)
                    # Skip these packages
                    ;;
                  *)
                    if [ -f "$pkg_json" ]; then
                      ${gsed}/bin/gsed -i '/"type": "module",/d' "$pkg_json"
                    fi
                    ;;
                esac
              done

              # 3) Modify percy.js in dist (if it exists after build)
              # This will be done in buildPhase after yarn build
            '';

            # Build phase: install dependencies, build, and transform
            buildPhase = ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"

              # Install dependencies
              echo "Installing dependencies..."
              yarn install --frozen-lockfile

              # Build all packages
              echo "Building packages..."
              yarn build

              # Modify percy.js in dist (must happen after build)
              if [ -f packages/cli/dist/percy.js ]; then
                echo "Modifying percy.js..."
                tmp=$(mktemp)
                printf "import { cli } from '@percy/cli';\n" > "$tmp"
                cat packages/cli/dist/percy.js >> "$tmp"
                mv "$tmp" packages/cli/dist/percy.js
              fi

              # Modify run.cjs to ensure NODE_ENV is set
              if [ -f packages/cli/bin/run.cjs ]; then
                echo "Modifying run.cjs..."
                # Check if NODE_ENV line already exists
                if ! grep -q 'process.env.NODE_ENV = "executable";' packages/cli/bin/run.cjs; then
                  ${gsed}/bin/gsed -i '1a process.env.NODE_ENV = "executable";' packages/cli/bin/run.cjs
                fi
              fi

              # Convert ES6 code to CommonJS
              echo "Building CommonJS..."
              npm run build_cjs

              # Copy build output to packages
              if [ -d build ]; then
                echo "Copying build output to packages..."
                cp -R build/* packages/
              fi
            '';

            # Install phase: use pkg to create executable
            installPhase = ''
              mkdir -p $out/bin

              echo "Packaging with pkg for target: ${pkgTarget}"

              # Run pkg to create executable
              # Use npx to get pkg, and specify the target
              npx -y pkg ./packages/cli/bin/run.js -t ${pkgTarget} -d

              # Find and move the resulting binary
              # pkg creates files with names like: run, run-linux, run-macos, run-win.exe
              binary_name=""
              if [ -f "run-${pkgTarget}" ]; then
                binary_name="run-${pkgTarget}"
              elif [ -f "run-linux" ] && [[ "${system}" == *"linux"* ]]; then
                binary_name="run-linux"
              elif [ -f "run-macos" ] && [[ "${system}" == *"darwin"* ]]; then
                binary_name="run-macos"
              elif [ -f "run" ]; then
                binary_name="run"
              else
                echo "Error: Could not find pkg output binary" >&2
                ls -la
                exit 1
              fi

              # Move to output with normalized name
              if [[ "${system}" == *"darwin"* ]]; then
                mv "$binary_name" $out/bin/percy
              elif [[ "${system}" == *"linux"* ]]; then
                mv "$binary_name" $out/bin/percy
              else
                mv "$binary_name" $out/bin/percy
              fi

              chmod +x $out/bin/percy
            '';

            meta = {
              description = "Percy CLI packaged via pkg";
              mainProgram = "percy";
            };
          };
        });

      # Convenience apps for local dev: `nix run .#percy-cli`
      apps = forAllSystems (system: {
        percy-cli = {
          type = "app";
          program = "${self.packages.${system}.percy-cli}/bin/percy";
        };
      });

      # Development shell (optional, can reuse existing shell.nix)
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              nodejs_14
              yarn
              git
              zip
              coreutils
              gnused
            ];
          };
        }
      );
    };
}

