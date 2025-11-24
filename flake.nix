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

        # Node.js 14 for compatibility with pkg
        nodejs = pkgs.nodejs-14_x;

      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Build tools
            gnumake
            gsed
            zip
            file
            
            # Node.js ecosystem
            nodejs
            yarn
          ];

          shellHook = ''
            echo "🐚 Percy CLI Development Shell"
            echo ""
            echo "Available tools:"
            echo "  - node: $(node --version)"
            echo "  - npm: $(npm --version)"
            echo "  - yarn: $(yarn --version)"
            echo "  - gsed: $(gsed --version | head -1)"
            echo ""
            echo "To build Linux ARM64 executable:"
            echo "  ./scripts/executable-local-linux.sh"
            echo ""
            
            # Install pkg globally if not already installed
            if ! command -v pkg &>/dev/null || ! pkg --version &>/dev/null; then
              echo "Installing pkg globally..."
              npm install -g pkg
            fi
          '';
        };
      });
}

