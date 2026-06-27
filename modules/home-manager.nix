{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.nu-nix;
in
{
  options.programs.nu-nix = {
    enable = lib.mkEnableOption "nu-nix: Nushell and Nix integration";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../package { };
      defaultText = lib.literalExpression "pkgs.callPackage ../package { }";
      description = ''
        The nu-nix package. Provides `nu-bash` and the `nu-nix` Nushell module
        under `share/nushell/nu-nix/`.
      '';
    };

    autoLoad = lib.mkEnableOption ''
      Automatically load the `nu-nix` module in every Nushell session by
      installing a file under the user's Nushell autoload directory.
    '';
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.packages = [
          pkgs.nushell
          cfg.package
        ];
      }

      (lib.mkIf cfg.autoLoad {
        xdg.configFile."nushell/autoload/nu-nix.nu".text = "use ${cfg.package}/share/nushell/nu-nix *\n";
      })
    ]
  );
}
