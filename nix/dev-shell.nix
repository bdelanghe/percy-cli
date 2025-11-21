{ pkgs }:

let
  # Firefox is not available on aarch64-darwin in nixpkgs 24.05
  # Use tryEval to safely check if Firefox can be evaluated
  firefox-eval = builtins.tryEval pkgs.firefox;
  firefox-available = firefox-eval.success;
  firefox-pkg = if firefox-available then firefox-eval.value else null;
  
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
  
  # Conditionally add Firefox only if available
  buildInputs = baseInputs ++ pkgs.lib.optional firefox-available firefox-pkg;
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

    # Try Nix Firefox first (if available), then system Firefox
    ${if firefox-available then ''
      if [ -f "${firefox-pkg}/bin/firefox" ]; then
        export FIREFOX_BIN="${firefox-pkg}/bin/firefox"
      elif [ -f "/Applications/Firefox.app/Contents/MacOS/firefox" ]; then
        export FIREFOX_BIN="/Applications/Firefox.app/Contents/MacOS/firefox"
      elif [ -n "$(command -v firefox)" ]; then
        export FIREFOX_BIN="$(command -v firefox)"
      else
        echo "WARNING: Firefox binary not found. Some tests may fail." >&2
      fi
    '' else ''
      # Nix Firefox not available on this platform, use system Firefox
      if [ -f "/Applications/Firefox.app/Contents/MacOS/firefox" ]; then
        export FIREFOX_BIN="/Applications/Firefox.app/Contents/MacOS/firefox"
      elif [ -n "$(command -v firefox)" ]; then
        export FIREFOX_BIN="$(command -v firefox)"
      else
        echo "WARNING: Firefox binary not found. Some tests may fail." >&2
      fi
    ''}
  '';
}

