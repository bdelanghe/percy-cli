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

    # Add name field to root package.json for mkYarnPackage compatibility
    if ! grep -q '"name":' package.json; then
      {
        echo '{'
        echo '  "name": "percy-cli",'
        tail -n +2 package.json
      } > package.json.tmp && mv package.json.tmp package.json
    fi

    # Remove "type": "module" from all package.json except dom and sdk-utils
    find packages -name package.json \
      -not -path "*/dom/*" \
      -not -path "*/sdk-utils/*" \
      -exec sed -i '/"type": "module",/d' {} \;
  '';
}

