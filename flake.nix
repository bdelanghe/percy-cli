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

      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Build tools
            gnumake
            gnused  # provides gsed
            zip
            file
            
            # Node.js ecosystem
            nodejs
            yarn
          ];

          shellHook = ''
            echo "🐚 Percy CLI Development Shell"
            echo ""
            
            # Set up npm prefix to user-writable location (Nix store is read-only)
            export NPM_CONFIG_PREFIX="$HOME/.local/npm-packages"
            export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"
            
            # Create alias for gsed if gnused doesn't provide it directly
            if ! command -v gsed &>/dev/null && command -v sed &>/dev/null; then
              alias gsed=sed
            fi
            
            echo "Available tools:"
            echo "  - node: $(node --version)"
            echo "  - npm: $(npm --version)"
            echo "  - yarn: $(yarn --version)"
            if command -v gsed &>/dev/null; then
              echo "  - gsed: $(gsed --version | head -1)"
            else
              echo "  - sed: $(sed --version 2>/dev/null | head -1 || echo 'GNU sed (via gnused)')"
            fi
            echo ""
            echo "To build Linux ARM64 executable:"
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
      });
}

