{ pkgs }:

let
  # Firefox is not available on aarch64-darwin in nixpkgs 24.05
  # Check platform first to avoid evaluating Firefox on unsupported platforms
  isAarch64Darwin = pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isAarch64;
  firefox-available = !isAarch64Darwin;
  
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
  
  # Don't include Firefox in buildInputs on aarch64-darwin (not available in nixpkgs 24.05)
  # The shellHook will handle finding Firefox from the system instead
  buildInputs = baseInputs;
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

    # Set Firefox binary path
    # Try system Firefox locations (Nix Firefox not available on aarch64-darwin in nixpkgs 24.05)
    if [ -f "/Applications/Firefox.app/Contents/MacOS/firefox" ]; then
      export FIREFOX_BIN="/Applications/Firefox.app/Contents/MacOS/firefox"
    elif [ -n "$(command -v firefox)" ]; then
      export FIREFOX_BIN="$(command -v firefox)"
    else
      echo "WARNING: Firefox binary not found. Some tests may fail." >&2
    fi
  '';
}

