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
      packages = eachSystem (system:
        let
          cliPackages = pkgsFor.${system}.callPackage ./default.nix {
            bunNix = ./bun.nix;
            # bun2nix functions are available via overlay (Pattern A)
            # No need to pass them explicitly - pkgs.bun2nix.* is available
          };
        in
        {
          # Option A: Nix-wrapped Node CLI (simpler, uses Node to run ESM)
          percy-cli-node = cliPackages.percy-cli-node;
          
          # Option B: Bun-compiled binary (true native binary with embedded Bun runtime)
          percy-cli = cliPackages.percy-cli;
          
          # Default to Bun-compiled binary for backward compatibility
          default = cliPackages.default;
          
          # Node tree (intermediate build artifact)
          node-tree = cliPackages.node-tree;
          
          # Diagnostic outputs for bun2nix offline cache troubleshooting
          # bun-deps: The offline cache derivation (for inspection)
          bun-deps = cliPackages.bun-deps;
          
          # bun-deps-verify: Verification info about bunDeps derivation
          bun-deps-verify = cliPackages.bun-deps-verify;
          
          # node-tree-manual: Fallback implementation using manual cache setup
          # Use this if mkDerivation hook is not working correctly
          node-tree-manual = cliPackages.node-tree-manual;
        }
      );

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
            # Install dependencies if bun.lock exists
            if [ -f bun.lock ]; then
              bun install --frozen-lockfile
            else
              echo "Warning: bun.lock not found. Run 'bun install' to generate it."
            fi
          '';
        };
      });

      apps = eachSystem (system:
        let
          bun = pkgsFor.${system}.bun;
          bun2nix = pkgsFor.${system}.bun2nix;
          nodejs = pkgsFor.${system}.nodejs;
          git = pkgsFor.${system}.git;
          typescript = pkgsFor.${system}.nodePackages.typescript;
          # Ensure Bun is in PATH for postinstall scripts
          bunPath = "${bun}/bin";
        in
        {
          # Generate bun.lock by running bun install
          bun-install = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "bun-install" ''
              set -e
              # Add Bun to PATH so postinstall scripts can find it
              export PATH="${bunPath}:$PATH"
              echo "Running bun install to generate bun.lock..."
              ${bun}/bin/bun install
              echo "✓ bun.lock generated"
            '');
          };

          # Generate bun.nix from bun.lock
          bun2nix-generate = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "bun2nix-generate" ''
              set -e
              if [ ! -f bun.lock ]; then
                echo "Error: bun.lock not found. Run 'nix run .#bun-install' first." >&2
                exit 1
              fi
              echo "Generating bun.nix from bun.lock..."
              ${bun2nix}/bin/bun2nix -l bun.lock -o bun.nix
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
              echo "Step 1: Running bun install to generate bun.lock..."
              echo "  (Skipping postinstall scripts - not needed for lockfile generation)"
              ${bun}/bin/bun install --ignore-scripts
              echo "✓ bun.lock generated"
              echo ""
              echo "Step 2: Generating bun.nix from bun.lock..."
              ${bun2nix}/bin/bun2nix -l bun.lock -o bun.nix
              echo "✓ bun.nix generated"
              echo ""
              echo "✓ Both lockfiles updated. Don't forget to commit:"
              echo "  git add bun.lock bun.nix"
            '');
          };

          # Run postinstall scripts for all packages
          postinstall = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "postinstall" ''
              set -e
              export PATH="${bunPath}:$PATH"
              ${bun}/bin/bun run --filter './packages/*' postinstall
            '');
          };

          # Build scripts
          build = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "build" ''
              set -e
              export PATH="${bunPath}:$PATH"
              ${bun}/bin/bun run --filter './packages/*' build
            '');
          };

          build-watch = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "build-watch" ''
              set -e
              export PATH="${bunPath}:$PATH"
              ${bun}/bin/bun run --filter './packages/*' build --watch
            '');
          };

          build-pack = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "build-pack" ''
              set -e
              export PATH="${bunPath}:$PATH"
              mkdir -p ./packs
              for pkg in packages/*; do
                (cd "$pkg" && ${bun}/bin/bun pack) && mv "$pkg"/*.tgz ./packs/ 2>/dev/null || true
              done
            '');
          };

          chromium-revision = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "chromium-revision" ''
              set -e
              export PATH="${nodejs}/bin:$PATH"
              ${nodejs}/bin/node ./scripts/chromium-revision.ts
            '');
          };

          clean = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "clean" ''
              set -e
              ${git}/bin/git clean -Xdf
            '');
          };

          lint = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "lint" ''
              set -e
              export PATH="${bunPath}:$PATH"
              ${bun}/bin/bun run --filter './packages/*' lint
            '');
          };

          readme = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "readme" ''
              set -e
              export PATH="${bunPath}:$PATH"
              ${bun}/bin/bun run --filter './packages/*' readme
            '');
          };

          test = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "test" ''
              set -e
              export PATH="${bunPath}:$PATH"
              ${bun}/bin/bun run --filter './packages/*' test
            '');
          };

          test-browser = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "test-browser" ''
              set -e
              export PATH="''$(pwd)/node_modules/.bin:''$PATH"
              if [ ! -f node_modules/.bin/vitest ]; then
                echo "Error: vitest not found. Run 'nix run .#bun-install' first." >&2
                exit 1
              fi
              ./node_modules/.bin/vitest run
            '');
          };

          test-watch = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "test-watch" ''
              set -e
              export PATH="''$(pwd)/node_modules/.bin:''$PATH"
              if [ ! -f node_modules/.bin/vitest ]; then
                echo "Error: vitest not found. Run 'nix run .#bun-install' first." >&2
                exit 1
              fi
              ./node_modules/.bin/vitest
            '');
          };

          test-coverage = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "test-coverage" ''
              set -e
              export PATH="${bunPath}:$PATH"
              ${bun}/bin/bun run --filter './packages/*' test:coverage
            '');
          };

          test-types = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "test-types" ''
              set -e
              export PATH="${bunPath}:$PATH"
              ${bun}/bin/bun run --filter './packages/*' test:types
            '');
          };

          # Comprehensive type checking, building, and linting
          check = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "check" ''
              set -e
              export PATH="${bunPath}:$PATH"
              
              echo "🔍 Running comprehensive checks..."
              echo ""
              
              # Step 1: Build all packages (generates .d.ts files)
              echo "📦 Step 1: Building all packages and generating type definitions..."
              ${bun}/bin/bun run --filter './packages/*' build
              echo "✓ Build complete"
              echo ""
              
              # Step 2: Type check all packages
              echo "🔎 Step 2: Running TypeScript type checks..."
              failed_packages=()
              for pkg in packages/*/; do
                pkg_name=$(basename "$pkg")
                tsconfig="$pkg/tsconfig.json"
                if [ -f "$tsconfig" ]; then
                  echo "  Checking $pkg_name..."
                  if ! ${typescript}/bin/tsc --project "$tsconfig" --noEmit 2>&1; then
                    failed_packages+=("$pkg_name")
                  else
                    echo "    ✓ $pkg_name"
                  fi
                fi
              done
              
              if [ ''${#failed_packages[@]} -gt 0 ]; then
                echo ""
                echo "❌ Type check failed for: ''${failed_packages[*]}"
                exit 1
              fi
              echo "✓ Type checks passed"
              echo ""
              
              # Step 3: Lint all packages
              echo "🧹 Step 3: Running linters..."
              ${bun}/bin/bun run --filter './packages/*' lint
              echo "✓ Linting complete"
              echo ""
              
              echo "✅ All checks passed!"
            '');
          };

          global-link = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "global-link" ''
              set -e
              export PATH="${bunPath}:$PATH"
              ${bun}/bin/bun link
            '');
          };

          global-unlink = {
            type = "app";
            program = toString (pkgsFor.${system}.writeShellScript "global-unlink" ''
              set -e
              export PATH="${bunPath}:$PATH"
              ${bun}/bin/bun unlink
            '');
          };
        });
    };
}
