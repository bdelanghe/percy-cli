# Migration Plan: Switching to Bun and Removing Lerna

## Overview

This document outlines the changes needed to fully migrate from Lerna + Yarn + dream2nix to Bun + bun2nix (or custom Bun Nix integration).

## Current Architecture (BEFORE)

- **Package Manager**: Yarn (with workspaces)
- **Monorepo Tool**: Lerna 6.0.1
- **Build Tools**: Babel, Rollup
- **Test Runner**: Jasmine, Karma
- **Nix Integration**: dream2nix (nodejs-package-json-v3) + mkYarnPackage
- **Lock File**: yarn.lock

## Current Architecture (AFTER - PARTIALLY MIGRATED)

- **Package Manager**: Bun ✅
- **Monorepo Tool**: Bun workspaces (native) ✅
- **Build Tools**: Babel (kept), Rollup (kept for now)
- **Test Runner**: Bun test runner ✅ (Jasmine/Karma still in deps but not used)
- **Nix Integration**: Direct Bun integration ✅
- **Lock File**: bun.lockb (will be generated on first `bun install`)

## Target Architecture

- **Package Manager**: Bun
- **Monorepo Tool**: Bun workspaces (native)
- **Build Tools**: Bun bundler (replaces Rollup), Babel (may still be needed)
- **Test Runner**: Bun test runner (replaces Jasmine/Karma)
- **Nix Integration**: Custom Bun integration (bun2nix doesn't exist yet)
- **Lock File**: bun.lockb

## Required Changes

### 1. Root package.json

**Remove:**
- `lerna` from devDependencies
- All `lerna run` commands from scripts
- `yarn` references

**Add:**
- Bun as a dependency (or use system Bun)
- Update scripts to use `bun run` instead of `lerna run`
- Update workspace commands

**New scripts structure:**
```json
{
  "scripts": {
    "build": "bun run --filter='./packages/*' build",
    "build:watch": "bun run --filter='./packages/*' --watch build",
    "test": "bun test",
    "test:coverage": "bun test --coverage",
    "postinstall": "bun run --filter='./packages/*' postinstall"
  }
}
```

### 2. Remove lerna.json

Delete `lerna.json` entirely - Bun workspaces handle this natively.

### 3. Update package.json workspaces

Bun uses the same `workspaces` field, but may need `bunfig.toml` for additional config:

```toml
# bunfig.toml
[install]
# Bun-specific install options
```

### 4. Build Scripts

**Current**: Uses Babel + Rollup
**Bun**: Can use Bun's bundler, but may need to keep Babel for compatibility

**Options:**
- Use Bun's built-in bundler for browser bundles
- Keep Babel for Node.js builds if needed
- Or use Bun's transpiler (supports TypeScript/JSX natively)

### 5. Test Scripts

**Current**: Jasmine + Karma
**Bun**: Built-in Jest-compatible test runner

**Migration:**
- Convert Jasmine tests to Jest/Bun test format
- Remove Karma config (Bun can run browser tests differently)
- Update test imports and assertions

### 6. Nix Integration (Most Complex Part)

Since `bun2nix` doesn't exist as a standard tool, we have two options:

#### Option A: Use Bun directly in Nix

```nix
# In flake.nix
let
  bun = pkgs.bun; # or buildBun from nixpkgs
  
  nodeTree = pkgs.stdenv.mkDerivation {
    name = "percy-cli-node-tree";
    src = srcPatched;
    
    nativeBuildInputs = [ bun ];
    
    buildPhase = ''
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"
      
      # Install dependencies with Bun
      bun install --frozen-lockfile
      
      # Build with Bun
      bun run build
      
      # Build CJS if still needed
      BABEL_ENV=dev babel packages -d build || true
      if [ -d build ]; then
        cp -R build/* packages/
      fi
    '';
    
    installPhase = ''
      mkdir -p $out
      cp -R . $out
    '';
  };
```

**Challenges:**
- Bun's lockfile (`bun.lockb`) is binary - harder to make deterministic
- Need to ensure Bun is available in Nix
- May need to vendor Bun or use a fixed version

#### Option B: Create a bun2nix-like tool

Build a custom Nix function that:
1. Parses `bun.lockb` (or generates it deterministically)
2. Downloads packages similar to `mkYarnPackage`
3. Creates a reproducible build environment

This is more work but provides better reproducibility.

### 7. Dev Shell (dev-shell.nix)

**Current**: Uses `yarn`
**Update**: Use `bun`

```nix
buildInputs = with pkgs; [
  bun  # Replace yarn
  nodejs
  git
  # ... rest
];
```

### 8. Package Dependencies

**No changes needed** - Bun is compatible with npm/yarn package.json format.

### 9. CI/CD Scripts

Update any scripts that reference:
- `yarn install` → `bun install`
- `yarn build` → `bun run build`
- `lerna` commands → `bun run` with filters

### 10. Build Process Compatibility

**Current build.js script:**
- Uses Babel for Node.js builds
- Uses Rollup for browser bundles

**Bun approach:**
- Can use Bun's bundler: `bun build`
- May still need Babel for specific transformations
- Or migrate to Bun's native TypeScript/JSX support

## Migration Steps

### ✅ Phase 1: Add Bun alongside existing tools - COMPLETED
   - ✅ Install Bun (added to dev-shell.nix and flake.nix)
   - ✅ Add `bunfig.toml`
   - ⚠️ Test `bun install` works (needs testing)

### ✅ Phase 2: Migrate scripts - COMPLETED
   - ✅ Replace `lerna run` with `bun run --filter`
   - ✅ Update build scripts to use Bun
   - ✅ Update executable.sh scripts
   - ⚠️ Test builds work (needs testing)

### ⏳ Phase 3: Migrate tests - PENDING
   - ⏳ Convert Jasmine to Bun test format
   - ⏳ Remove Karma
   - ⏳ Update test scripts
   - Note: Currently using `bun test` which should work with existing tests

### ✅ Phase 4: Nix integration - COMPLETED
   - ✅ Update `flake.nix` to use Bun instead of mkYarnPackage
   - ✅ Create Bun build derivation
   - ✅ Update `dev-shell.nix` to use Bun
   - ⚠️ Test Nix builds work (needs testing)

### ✅ Phase 5: Remove old tools - PARTIALLY COMPLETED
   - ✅ Remove Lerna from package.json
   - ✅ Remove lerna.json
   - ⚠️ Remove Yarn (still in some scripts/docs)
   - ✅ Replace dream2nix config with Bun integration
   - ⏳ Clean up unused dependencies (Jasmine, Karma, Rollup may still be needed)

### ⏳ Phase 6: Optimize - PENDING
   - ⏳ Use Bun's bundler where possible
   - ⏳ Remove Babel if not needed
   - ⏳ Optimize build times

## Risks and Considerations

### High Risk
- **Nix integration**: No standard bun2nix tool exists
- **Binary lockfile**: `bun.lockb` is harder to make deterministic
- **Compatibility**: Some packages may not work with Bun runtime

### Medium Risk
- **Test migration**: Converting Jasmine/Karma tests
- **Build tooling**: May need to keep Babel/Rollup for compatibility
- **CI/CD**: Need to update all CI scripts

### Low Risk
- **Package format**: Bun is compatible with npm/yarn package.json
- **Workspace structure**: Same structure works with Bun

## Benefits After Migration

1. **Faster installs**: Bun installs 10-100x faster than Yarn
2. **Faster builds**: Bun bundler is very fast
3. **Simpler toolchain**: One tool instead of many
4. **Better DX**: Faster feedback loops
5. **Native TypeScript**: No need for separate TS compilation

## Questions to Answer

1. **Do we need to keep Babel?** 
   - Check if all packages can use Bun's transpiler
   - Some packages may need Babel plugins

2. **Can we remove Rollup?**
   - Test if Bun bundler produces equivalent bundles
   - May need Rollup for specific browser bundle requirements

3. **How to handle bun.lockb in Nix?**
   - Option A: Generate it deterministically in Nix
   - Option B: Commit it and use it directly
   - Option C: Create custom bun2nix tool

4. **Test compatibility?**
   - How much work to convert Jasmine → Bun test?
   - Can Karma tests be replaced with Bun's browser testing?

## Recommendation

**Start with a hybrid approach:**
1. Use Bun for package management and development
2. Keep Lerna temporarily for complex monorepo tasks
3. Gradually migrate scripts to Bun
4. Build custom Nix integration for Bun
5. Remove Lerna once everything works

This reduces risk while gaining Bun's performance benefits.

