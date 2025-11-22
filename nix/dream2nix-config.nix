# dream2nix configuration for Percy CLI monorepo
# This configures dream2nix to build node_modules from yarn.lock

{ config, lib, ... }:

{
  # Package name
  name = "percy-cli";
  
  # Use yarn-lock translator
  translator = "yarn-lock";
  
  # Subsystem info for Node.js
  subsystemInfo = {
    nodejs = 20;
  };
  
  # Settings
  settings = {
    # Include devDependencies (needed for lerna, babel, etc.)
    includeDevDependencies = true;
  };
}

