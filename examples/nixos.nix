# NixOS consumer module for a project-provided Nushell session.
#
# The surrounding host flake supplies both inputs to modules:
#
#   inputs.nu-nix.url = "github:cwd-k2/nu-nix";
#   inputs.project.url = "path:./path/to/project";
#   inputs.project.inputs.nu-nix.follows = "nu-nix";
#
#   nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
#     specialArgs = { inherit inputs; };
#     modules = [ ./nixos.nix ];
#   };
#
# `project` can be any flake exposing a session as `packages.<system>.session`;
# examples/integrated-project is the local reference implementation.

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
  imports = [ inputs.nu-nix.nixosModules.default ];

  # Make nu-nix commands available in every newly started Nushell.
  programs.nu-nix = {
    enable = true;
    autoLoad = true;
  };

  # Install the project's composed launcher as an ordinary Nix package.
  # Run `nu-nix-integrated-session` only when that project context is wanted.
  environment.systemPackages = [ projectSession ];

  # If a compatibility login shell is also desired, add `config` to this
  # module's arguments and opt in independently:
  # users.users.alice.shell = config.programs.nu-nix.loginShellPackage;
}
