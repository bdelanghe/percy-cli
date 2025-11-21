{ pkgs }:

let
  # Firefox is not available on aarch64-darwin in nixpkgs 24.05
  # Check platform before trying to evaluate Firefox
  is-aarch64-darwin = pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isAarch64;
  
  # Base build inputs (always included)
  baseInputs = with pkgs; [
    nodejs
    yarn
    git
    zip
    coreutils
    act
    gnused
  ];
  
  # Conditionally add Firefox only if not on aarch64-darwin
  buildInputs = baseInputs ++ (
    if is-aarch64-darwin then [] else [ pkgs.firefox ]
  );
in

pkgs.mkShell {
  inherit buildInputs;

  shellHook = ''
    export PATH="$PWD/node_modules/.bin:$PATH"
    if [ -d /opt/homebrew/bin ]; then
      export PATH="/opt/homebrew/bin:$PATH"
    elif [ -d /usr/local/bin ]; then
      export PATH="/usr/local/bin:$PATH"
    fi

    # Try system Firefox (Nix Firefox not available on aarch64-darwin)
    if [ -f "/Applications/Firefox.app/Contents/MacOS/firefox" ]; then
      export FIREFOX_BIN="/Applications/Firefox.app/Contents/MacOS/firefox"
    elif [ -n "$(command -v firefox)" ]; then
      export FIREFOX_BIN="$(command -v firefox)"
    else
      echo "WARNING: Firefox binary not found. Some tests may fail." >&2
    fi
  '';
}

