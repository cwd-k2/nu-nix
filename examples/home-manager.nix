# Home Manager consumer module for the same project session as nixos.nix.
#
# In the surrounding flake, pass the inputs to Home Manager modules:
#
#   homeConfigurations.alice = home-manager.lib.homeManagerConfiguration {
#     inherit pkgs;
#     extraSpecialArgs = { inherit inputs; };
#     modules = [ ./home-manager.nix ];
#   };
#
# The expected inputs are `nu-nix` and a `project` flake exposing
# `packages.<system>.session` (such as examples/integrated-project).

{
  inputs,
  pkgs,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;
  projectSession = inputs.project.packages.${system}.session;
in
{
  imports = [ inputs.nu-nix.homeManagerModules.default ];

  # Make nu-nix commands available in every newly started Nushell.
  programs.nu-nix = {
    enable = true;
    autoLoad = true;
  };

  # This installs a launcher; it does not inject project modules or plugins
  # into unrelated Nushell processes.
  home.packages = [ projectSession ];
}
