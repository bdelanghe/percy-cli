{ pkgs }:

let
  # Firefox is not available on aarch64-darwin in nixpkgs 24.05
  # Use tryEval to safely check if Firefox is available
  firefox-available = pkgs.lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.firefox;
in

pkgs.mkShell {
  buildInputs = with pkgs; [
    nodejs
    yarn
    git
    zip
    coreutils
    act
    gnused
  ] ++ pkgs.lib.optional firefox-available pkgs.firefox;

  shellHook = ''
    export PATH="$PWD/node_modules/.bin:$PATH"
    if [ -d /opt/homebrew/bin ]; then
      export PATH="/opt/homebrew/bin:$PATH"
    elif [ -d /usr/local/bin ]; then
      export PATH="/usr/local/bin:$PATH"
    fi

    # Try Nix Firefox first (if available), then system Firefox
    if ${if firefox-available then ''[ -f "${pkgs.firefox}/bin/firefox" ]'' else "false"}; then
      export FIREFOX_BIN="${pkgs.firefox}/bin/firefox"
    elif [ -f "/Applications/Firefox.app/Contents/MacOS/firefox" ]; then
      export FIREFOX_BIN="/Applications/Firefox.app/Contents/MacOS/firefox"
    else
      echo "WARNING: Firefox binary not found. Using system Firefox if available." >&2
    fi
  '';
}

