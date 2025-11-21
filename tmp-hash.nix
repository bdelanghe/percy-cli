let
  flake = builtins.getFlake (toString ./.);
  nixpkgs = builtins.getFlake "github:NixOS/nixpkgs/b134951a4c9f3c995fd7be05f3243f8ecd65d798";
  pkgs = import nixpkgs { system = "aarch64-darwin"; };
in
pkgs.fetchYarnDeps {
  yarnLock = ./yarn.lock;
  hash = "";
}

