{ pkgs ? import <nixpkgs> {} }:

let
  firefox-bin = "${pkgs.firefox}/bin/firefox";
in

pkgs.mkShell {
  buildInputs = with pkgs; [
    nodejs
    yarn
    git
    zip
    coreutils
    firefox
    act
  ];

  shellHook = ''
    export PATH="$PWD/node_modules/.bin:$PATH"
    # Ensure brew is available in PATH (for Intel Mac: /usr/local/bin, for Apple Silicon: /opt/homebrew/bin)
    if [ -d /opt/homebrew/bin ]; then
      export PATH="/opt/homebrew/bin:$PATH"
    elif [ -d /usr/local/bin ]; then
      export PATH="/usr/local/bin:$PATH"
    fi
    # Set Firefox binary for karma tests using direct Nix store path, fallback to system Firefox
    if [ -f "${firefox-bin}" ]; then
      export FIREFOX_BIN="${firefox-bin}"
    elif [ -f "/Applications/Firefox.app/Contents/MacOS/firefox" ]; then
      export FIREFOX_BIN="/Applications/Firefox.app/Contents/MacOS/firefox"
    else
      echo "ERROR: Firefox binary not found. Expected one of:" >&2
      echo "  - Nix Firefox: ${firefox-bin}" >&2
      echo "  - System Firefox: /Applications/Firefox.app/Contents/MacOS/firefox" >&2
      echo "Please install Firefox or ensure it's available in the Nix environment." >&2
      exit 1
    fi
  '';
}
