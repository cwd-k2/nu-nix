{
  imports = [
    /home/nixos/Projects/nu-nix/modules/nu-nix.nix
  ];

  programs.nu-nix.enable = true;

  users.users.nixos.shell = "/run/current-system/sw/bin/nu-bash";
}
