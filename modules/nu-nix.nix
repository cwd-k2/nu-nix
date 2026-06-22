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

    loginShellUser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "nixos";
      description = ''
        User whose login shell should be set to nu-bash. Set to null to only
        install the commands and register nu-bash as an allowed shell.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = [
          pkgs.nushell
          cfg.package
        ];

        environment.shells = [
          "${cfg.package}/bin/nu-bash"
          pkgs.bashInteractive
        ];
      }

      (lib.mkIf (cfg.loginShellUser != null) {
        users.users.${cfg.loginShellUser}.shell =
          lib.mkForce "${cfg.package}/bin/nu-bash";
      })
    ]
  );
}
