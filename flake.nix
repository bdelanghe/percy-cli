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
          # Project requires Node >=14, so Node 20 is compatible
          node = pkgs.nodejs_20;
          yarn = pkgs.yarn;
          gsed = pkgs.gnused;
          zip = pkgs.zip;

          # Get pkg via npx (will be available in buildPhase)
          pkgNode = pkgs.nodePackages_latest.pkg;

          # Map Nix system to pkg target
          # Using node20 targets since we're building with Node 20
          systemToPkgTarget = {
            "x86_64-linux" = "node20-linux-x64";
            "aarch64-linux" = "node20-linux-arm64";
            "x86_64-darwin" = "node20-macos-x64";
            "aarch64-darwin" = "node20-macos-arm64";
          };

          pkgTarget = systemToPkgTarget.${system};

        in rec {
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
              # pkg creates files with names based on target:
              # - For linux: run-linux, run-linux-arm64, or just run
              # - For macos: run-macos, run-macos-arm64, or just run
              binary_name=""
              
              # Check for architecture-specific names first
              if [[ "${system}" == "aarch64-linux" ]] && [ -f "run-linux-arm64" ]; then
                binary_name="run-linux-arm64"
              elif [[ "${system}" == "aarch64-darwin" ]] && [ -f "run-macos-arm64" ]; then
                binary_name="run-macos-arm64"
              elif [[ "${system}" == *"linux"* ]] && [ -f "run-linux" ]; then
                binary_name="run-linux"
              elif [[ "${system}" == *"darwin"* ]] && [ -f "run-macos" ]; then
                binary_name="run-macos"
              elif [ -f "run" ]; then
                binary_name="run"
              else
                echo "Error: Could not find pkg output binary" >&2
                echo "Looking for binary for system: ${system}, target: ${pkgTarget}" >&2
                echo "Files in current directory:" >&2
                ls -la
                exit 1
              fi

              # Move to output with normalized name
              mv "$binary_name" $out/bin/percy

              chmod +x $out/bin/percy
            '';

            meta = {
              description = "Percy CLI packaged via pkg";
              mainProgram = "percy";
            };
          };

          # Default package for `nix build` (without specifying a package name)
          default = percy-cli;
        });

      # Convenience apps for local dev: `nix run .#percy-cli`
      apps = forAllSystems (system: {
        percy-cli = {
          type = "app";
          program = "${self.packages.${system}.percy-cli}/bin/percy";
          meta = {
            description = "Percy CLI executable";
          };
        };
      });

      # Development shell (optional, can reuse existing shell.nix)
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in {
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
        }
      );
    };
}

