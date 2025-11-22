{
  description = "Percy CLI - Built with Bun and bun2nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";

    bun2nix.url = "github:nix-community/bun2nix?tag=2.0.1";
    bun2nix.inputs.nixpkgs.follows = "nixpkgs";
    bun2nix.inputs.systems.follows = "systems";
  };

  # Use the cached version of bun2nix from the nix-community cache
  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  outputs =
    inputs:
    let
      # Read each system from the nix-systems input
      eachSystem = inputs.nixpkgs.lib.genAttrs (import inputs.systems);

      # Access the package set for a given system with bun2nix overlay
      pkgsFor = eachSystem (
        system:
        import inputs.nixpkgs {
          inherit system;
          # Use the bun2nix overlay, which puts `bun2nix` in pkgs
          overlays = [ inputs.bun2nix.overlays.default ];
        }
      );
    in
    {
      packages = eachSystem (system: {
        # Main Percy CLI binary (default package)
        default = pkgsFor.${system}.callPackage ./default.nix {
          bunNix = ./bun.nix;
        };

        # Expose all build layers for debugging and incremental builds
        percy-cli = pkgsFor.${system}.callPackage ./default.nix {
          bunNix = ./bun.nix;
        };
      });

      devShells = eachSystem (system: {
        default = pkgsFor.${system}.mkShell {
          packages = with pkgsFor.${system}; [
            bun
            nodejs
            git
            # Add the bun2nix binary to our devshell for regenerating bun.nix
            bun2nix
          ];

          shellHook = ''
            # Install dependencies if bun.lockb exists
            if [ -f bun.lockb ]; then
              bun install --frozen-lockfile
            else
              echo "Warning: bun.lockb not found. Run 'bun install' to generate it."
            fi
          '';
        };
      });

      apps = eachSystem (system:
        let
          bun = pkgsFor.${system}.bun;
          bun2nix = pkgsFor.${system}.bun2nix;
          # Ensure Bun is in PATH for postinstall scripts
          bunPath = "${bun}/bin";
        in
        {
          # Generate bun.lockb by running bun install
          bun-install = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "bun-install" ''
              set -e
              # Add Bun to PATH so postinstall scripts can find it
              export PATH="${bunPath}:$PATH"
              echo "Running bun install to generate bun.lockb..."
              ${bun}/bin/bun install
              echo "✓ bun.lockb generated"
            '');
          };

          # Generate bun.nix from bun.lockb
          bun2nix-generate = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "bun2nix-generate" ''
              set -e
              if [ ! -f bun.lockb ]; then
                echo "Error: bun.lockb not found. Run 'nix run .#bun-install' first." >&2
                exit 1
              fi
              echo "Generating bun.nix from bun.lockb..."
              ${bun2nix}/bin/bun2nix -o bun.nix
              echo "✓ bun.nix generated"
            '');
          };

          # Update both lockfiles (bun install + bun2nix)
          update-lockfiles = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "update-lockfiles" ''
              set -e
              # Add Bun to PATH so postinstall scripts can find it
              export PATH="${bunPath}:$PATH"
              echo "Step 1: Running bun install to generate bun.lockb..."
              ${bun}/bin/bun install
              echo "✓ bun.lockb generated"
              echo ""
              echo "Step 2: Generating bun.nix from bun.lockb..."
              ${bun2nix}/bin/bun2nix -o bun.nix
              echo "✓ bun.nix generated"
              echo ""
              echo "✓ Both lockfiles updated. Don't forget to commit:"
              echo "  git add bun.lockb bun.nix"
            '');
          };
        });
    };
}
