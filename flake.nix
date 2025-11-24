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
            # Find the project root (where flake.nix is located)
            SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(cd "$SCRIPT_DIR/../.." && pwd)")"
            cd "$PROJECT_ROOT" || { echo "Error: Could not find project root"; exit 1; }
            
            # Set up npm prefix to user-writable location (Nix store is read-only)
            export NPM_CONFIG_PREFIX="$HOME/.local/npm-packages"
            export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"
            
            # Install pkg to user-writable location if not already installed
            if ! command -v pkg &>/dev/null || ! pkg --version &>/dev/null; then
              echo "Installing pkg to $NPM_CONFIG_PREFIX..."
              mkdir -p "$NPM_CONFIG_PREFIX"
              npm install -g pkg
            fi
            
            # Run the executable build script
            exec bash ./scripts/executable-local-linux.sh
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

