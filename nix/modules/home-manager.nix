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
      default = pkgs.callPackage ../packages/nu-nix.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../packages/nu-nix.nix { }";
      description = ''
        The nu-nix integration package. Provides the native plugin and the
        Nushell module under `share/nushell/nu-nix/`. Exact integrated commands
        use the `nix` namespace, other commands fall through to the CLI, and
        `^nix` always selects the raw executable.
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
        xdg.configFile."nushell/autoload/nu-nix.nu".text = ''
          plugin use --plugin-config ${cfg.package}/share/nushell/nu-nix/plugin.msgpackz nix
          use ${cfg.package}/share/nushell/nu-nix *
        '';
      })
    ]
  );
}
