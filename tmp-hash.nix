let
  flake = builtins.getFlake (toString ./.);
  pkgs = import <nixpkgs> { system = "aarch64-darwin"; };
in
pkgs.fetchYarnDeps {
  yarnLock = ./yarn.lock;
  hash = "";
}

