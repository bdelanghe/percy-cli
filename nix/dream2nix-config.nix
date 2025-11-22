# dream2nix configuration for Percy CLI monorepo
# This configures dream2nix to build the entire Node.js package including devDependencies

{ dream2nix, config, lib, srcPatched, ... }:

{
  imports = [
    dream2nix.modules.dream2nix.mkDerivation
  ];

  # Package name
  name = "percy-cli";
  
  # mkDerivation configuration
  mkDerivation = {
    src = srcPatched;
    
    # Build phase - run lerna and babel
    buildPhase = ''
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"

      # Add node_modules/.bin to PATH for build tools
      export PATH="$PWD/node_modules/.bin:$PATH"

      # Run lerna build
      lerna run build --stream

      # Run babel build_cjs directly
      BABEL_ENV=dev babel packages -d build || true
      if [ -d build ]; then
        cp -R build/* packages/
      fi
    '';
  };
}
