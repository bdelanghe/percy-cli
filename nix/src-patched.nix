# nix/src-patched.nix
# Layer 1: Patches the Percy CLI source tree to remove "type": "module" declarations
# This must happen early so all build steps see consistent CJS semantics

{ pkgs, version, src ? ../. }:

let
  inherit (pkgs) stdenv gnused lib;
in

stdenv.mkDerivation {
  pname = "percy-cli-src-patched";
  inherit version;

  src = lib.cleanSource src;
  sourceRoot = "source";
  nativeBuildInputs = with pkgs; [ gnused jq ];
  dontBuild = true;

  installPhase = ''
    mkdir -p $out
    cp -R . $out
    cd $out

    # Remove "type": "module" from root package.json
    sed -i '/"type": "module",/d' package.json

    # Remove "type": "module" from all package.json except dom and sdk-utils
    find packages -name package.json \
      -not -path "*/dom/*" \
      -not -path "*/sdk-utils/*" \
      -exec sed -i '/"type": "module",/d' {} \;

    # Add bun2nix postinstall script to root package.json
    # This will generate bun.nix after bun install runs
    # Merge with existing postinstall if present
    if jq -e '.scripts.postinstall' package.json >/dev/null 2>&1; then
      # Existing postinstall - append bun2nix
      jq '.scripts.postinstall = (.scripts.postinstall + " && bun2nix -o bun.nix")' package.json > package.json.tmp && mv package.json.tmp package.json
    else
      # No existing postinstall - add new one
      jq '.scripts.postinstall = "bun2nix -o bun.nix"' package.json > package.json.tmp && mv package.json.tmp package.json
    fi
  '';
}

