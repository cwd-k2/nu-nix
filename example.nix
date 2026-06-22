{
  imports = [
    /home/nixos/Projects/nu-nix/modules/nu-nix.nix
  ];

  programs.nu-nix = {
    enable = true;
    loginShellUser = "nixos";
  };
}
