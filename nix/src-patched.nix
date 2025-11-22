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
  nativeBuildInputs = [ gnused ];
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
  '';
}

