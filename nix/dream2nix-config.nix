# dream2nix configuration for Percy CLI monorepo
# This configures dream2nix to build the entire Node.js package including devDependencies

{ dream2nix, config, lib, srcPatched, ... }:

{
  # Import required dream2nix modules
  # nodejs-package-json-v3 is the stable translator for yarn.lock (see https://dream2nix.dev/reference/nodejs-package-json-v3/)
  # mkDerivation provides the build derivation (includes library functions)
  imports = [
    dream2nix.modules.dream2nix.nodejs-package-json-v3
    dream2nix.modules.dream2nix.mkDerivation
  ];

  # Package name
  name = "percy-cli";
  
  # Project root (valid top-level option)
  # dream2nix will auto-detect package.json and yarn.lock from here
  paths.projectRoot = srcPatched;
  
  # Configure the nodejs-package-json-v3 translator
  # This tells dream2nix to use yarn.lock for dependency resolution
  # See https://dream2nix.dev/reference/nodejs-package-json-v3/ for available options
  nodejs-package-json-v3 = {
    packageJson = "${srcPatched}/package.json";
    yarnLock = "${srcPatched}/yarn.lock";
  };
  
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
