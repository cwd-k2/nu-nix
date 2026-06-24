# Minimal NixOS configuration using nu-nix.
#
# Adapt the relevant options into your existing configuration.nix / flake setup.
#
# With a flake:
#
#   inputs.nu-nix.url = "github:cwd-k2/nu-nix";
#
#   outputs = { nixpkgs, nu-nix, ... }: {
#     nixosConfigurations.mymachine = nixpkgs.lib.nixosSystem {
#       modules = [ nu-nix.nixosModules.default ./configuration.nix ];
#     };
#   };

{ config, lib, pkgs, ... }:

{
  # Install nu-bash (login-shell wrapper) and the nu-nix Nushell module.
  programs.nu-nix.enable = true;

  # Add the module directory to $env.NU_LIB_DIRS so that
  #   use nu-nix *
  # works in any Nushell session without a full path.
  # Requires programs.nushell.enable = true.
  programs.nu-nix.autoLoad = true;

  # Enable the system-level Nushell configuration (required by autoLoad).
  programs.nushell.enable = true;

  # Make nu-bash the login shell for a user.
  # nu-bash routes interactive terminals to Nushell and everything else to Bash,
  # keeping compatibility with PAM, SSH, WSL launchers, and nix itself.
  users.users.alice = {
    isNormalUser = true;
    shell = lib.getExe' config.programs.nu-nix.package "nu-bash";
  };
}
