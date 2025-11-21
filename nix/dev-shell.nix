{ pkgs }:

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
    gnused
  ];

  shellHook = ''
    export PATH="$PWD/node_modules/.bin:$PATH"
    if [ -d /opt/homebrew/bin ]; then
      export PATH="/opt/homebrew/bin:$PATH"
    elif [ -d /usr/local/bin ]; then
      export PATH="/usr/local/bin:$PATH"
    fi

    if [ -f "${firefox-bin}" ]; then
      export FIREFOX_BIN="${firefox-bin}"
    elif [ -f "/Applications/Firefox.app/Contents/MacOS/firefox" ]; then
      export FIREFOX_BIN="/Applications/Firefox.app/Contents/MacOS/firefox"
    else
      echo "WARNING: Firefox binary not found." >&2
    fi
  '';
}

