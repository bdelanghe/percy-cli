let
  nixpkgs = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/b134951a4c9f3c995fd7be05f3243f8ecd65d798.tar.gz";
    sha256 = "sha256-OnSAY7XDSx7CtDoqNh8jwVwh4xNL/2HaJxGjryLWzX8=";
  };
  pkgs = import nixpkgs { system = "aarch64-darwin"; };
in
pkgs.fetchYarnDeps {
  yarnLock = ./yarn.lock;
  hash = "";
}

