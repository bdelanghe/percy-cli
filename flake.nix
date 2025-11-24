{
  description = "Percy CLI development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        # Use latest Node.js - pkg will use Node 18 from the --targets flag anyway
        nodejs = pkgs.nodejs;

        # Create gsed command from gnused
        gsed = pkgs.writeShellScriptBin "gsed" ''
          exec ${pkgs.gnused}/bin/sed "$@"
        '';

        # Shared build inputs for both devShell and run command
        buildInputs = with pkgs; [
          # Build tools
          gnumake
          gnused
          gsed  # gsed command wrapper
          zip
          file
          
          # Node.js ecosystem
          nodejs
          yarn
        ];

        # Shell script that sets up environment and runs the executable build
        buildExecutable = pkgs.writeShellApplication {
          name = "build-executable";
          runtimeInputs = buildInputs;
          text = ''
            # Find project root
            PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
            [ -z "$PROJECT_ROOT" ] && {
              DIR="$PWD"
              while [ "$DIR" != "/" ]; do
                [ -f "$DIR/flake.nix" ] && PROJECT_ROOT="$DIR" && break
                DIR="$(dirname "$DIR")"
              done
            }
            
            [ -z "$PROJECT_ROOT" ] || [ ! -f "$PROJECT_ROOT/scripts/executable-local-linux.sh" ] && {
              echo "Error: Could not find project root or executable script"
              echo "Please run 'nix run' from the project root directory"
              exit 1
            }
            
            cd "$PROJECT_ROOT" || exit 1
            
            # Environment setup: npm prefix for user-writable location
            export NPM_CONFIG_PREFIX="$HOME/.local/npm-packages"
            export PATH="$NPM_CONFIG_PREFIX/bin:''${PATH}"
            # Note: runtimeInputs (gsed, yarn, node, zip, file) are automatically in PATH
            
            # Tool setup: ensure pkg is installed
            command -v pkg >/dev/null 2>&1 || {
              echo "Installing pkg to $NPM_CONFIG_PREFIX..."
              mkdir -p "$NPM_CONFIG_PREFIX"
              npm install -g pkg
            }
            
            # Run build script (all tools guaranteed by Nix runtimeInputs)
            bash ./scripts/executable-local-linux.sh
            exit $?
          '';
        };

      in
      {
        devShells.default = pkgs.mkShell {
          inherit buildInputs;

          shellHook = ''
            echo "🐚 Percy CLI Development Shell"
            echo ""
            
            # Set up npm prefix to user-writable location (Nix store is read-only)
            export NPM_CONFIG_PREFIX="$HOME/.local/npm-packages"
            export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"
            
            echo "Available tools:"
            echo "  - node: $(node --version)"
            echo "  - npm: $(npm --version)"
            echo "  - yarn: $(yarn --version)"
            echo "  - gsed: $(gsed --version | head -1)"
            echo ""
            echo "To build Linux ARM64 executable:"
            echo "  nix run"
            echo "  or"
            echo "  ./scripts/executable-local-linux.sh"
            echo ""
            
            # Install pkg to user-writable location if not already installed
            if ! command -v pkg &>/dev/null || ! pkg --version &>/dev/null; then
              echo "Installing pkg to $NPM_CONFIG_PREFIX..."
              mkdir -p "$NPM_CONFIG_PREFIX"
              npm install -g pkg
            fi
          '';
        };

        apps.default = {
          type = "app";
          program = "${buildExecutable}/bin/build-executable";
        };
      });
}

