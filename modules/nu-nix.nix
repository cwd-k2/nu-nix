{ config, lib, pkgs, ... }:

let
  cfg = config.programs.nu-nix;
in
{
  options.programs.nu-nix = {
    enable = lib.mkEnableOption "nu-nix Nushell and Nix integration helpers";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../package { };
      defaultText = lib.literalExpression "pkgs.callPackage ../package { }";
      description = "Package that provides nu-nix and nu-bash.";
    };

  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.nushell
      cfg.package
    ];

    environment.shells = [
      "${cfg.package}/bin/nu-bash"
      pkgs.bashInteractive
    ];
  };
}
