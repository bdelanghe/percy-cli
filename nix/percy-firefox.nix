{ pkgs }:

let
  # Firefox is not available on aarch64-darwin in nixpkgs 24.05
  isAarch64Darwin =
    pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isAarch64;

  # Base build inputs (common to all platforms)
  baseInputs = with pkgs; [
    nodejs
    yarn
    git
    zip
    coreutils
    act
    gnused
  ];

  # Only add Nix Firefox where it's actually available
  buildInputs =
    if isAarch64Darwin then
      baseInputs
    else
      baseInputs ++ [ pkgs.firefox ];
in
pkgs.mkShell {
  inherit buildInputs;

  shellHook = ''
    # Expose local node_modules binaries
    export PATH="$PWD/node_modules/.bin:$PATH"

    # Homebrew PATH for macOS
    if [ -d /opt/homebrew/bin ]; then
      export PATH="/opt/homebrew/bin:$PATH"
    elif [ -d /usr/local/bin ]; then
      export PATH="/usr/local/bin:$PATH"
    fi

    # Set Firefox binary path:
    #   - Nix Firefox where available
    #   - System Firefox on macOS
    #   - Fallback to whatever "firefox" is on PATH
    if [ -x "${pkgs.firefox}/bin/firefox" ] 2>/dev/null; then
      export FIREFOX_BIN="${pkgs.firefox}/bin/firefox"
    elif [ -f "/Applications/Firefox.app/Contents/MacOS/firefox" ]; then
      export FIREFOX_BIN="/Applications/Firefox.app/Contents/MacOS/firefox"
    elif command -v firefox >/dev/null 2>&1; then
      export FIREFOX_BIN="$(command -v firefox)"
    else
      echo "WARNING: Firefox binary not found. Some tests may fail." >&2
    fi
  '';
}

