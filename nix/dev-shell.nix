{ pkgs }:

let
  # Firefox is not available on aarch64-darwin in nixpkgs 24.05
  # Use system Firefox on macOS, or Nix Firefox on Linux
  firefox-available = pkgs.firefox.meta.availableOn pkgs.stdenv.hostPlatform;
  firefox-bin = if firefox-available then "${pkgs.firefox}/bin/firefox" else null;
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

    if [ -n "${if firefox-bin != null then firefox-bin else ""}" ] && [ -f "${if firefox-bin != null then firefox-bin else ""}" ]; then
      export FIREFOX_BIN="${if firefox-bin != null then firefox-bin else ""}"
    elif [ -f "/Applications/Firefox.app/Contents/MacOS/firefox" ]; then
      export FIREFOX_BIN="/Applications/Firefox.app/Contents/MacOS/firefox"
    else
      echo "WARNING: Firefox binary not found. Using system Firefox if available." >&2
    fi
  '';
}

