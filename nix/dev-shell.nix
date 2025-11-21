{ pkgs }:

let
  # Firefox is not available on aarch64-darwin in nixpkgs 24.05
  # Check platform first to avoid evaluating Firefox on unsupported platforms
  isAarch64Darwin = pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isAarch64;
  
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
  
  # Only add Nix Firefox where it's actually available
  # On aarch64-darwin, the shellHook will handle finding Firefox from the system instead
  buildInputs =
    if isAarch64Darwin then
      baseInputs
    else
      baseInputs ++ [ pkgs.firefox ];
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

    # Set Firefox binary path:
    #   - Nix Firefox where available (not on aarch64-darwin)
    #   - System Firefox on macOS
    #   - Fallback to whatever "firefox" is on PATH
    ${if isAarch64Darwin then ''
    # Skip Nix Firefox check on aarch64-darwin (not available)
    if [ -f "/Applications/Firefox.app/Contents/MacOS/firefox" ]; then
      export FIREFOX_BIN="/Applications/Firefox.app/Contents/MacOS/firefox"
    elif command -v firefox >/dev/null 2>&1; then
      export FIREFOX_BIN="$(command -v firefox)"
    else
      echo "WARNING: Firefox binary not found. Some tests may fail." >&2
    fi
    '' else ''
    if [ -x "${pkgs.firefox}/bin/firefox" ] 2>/dev/null; then
      export FIREFOX_BIN="${pkgs.firefox}/bin/firefox"
    elif [ -f "/Applications/Firefox.app/Contents/MacOS/firefox" ]; then
      export FIREFOX_BIN="/Applications/Firefox.app/Contents/MacOS/firefox"
    elif command -v firefox >/dev/null 2>&1; then
      export FIREFOX_BIN="$(command -v firefox)"
    else
      echo "WARNING: Firefox binary not found. Some tests may fail." >&2
    fi
    ''}
  '';
}
