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
        The nu-nix package. Provides `nu-bash` (login-shell wrapper) and
        the `nu-nix` Nushell module under `share/nushell/nu-nix/`.
      '';
    };

    autoLoad = lib.mkEnableOption ''
      Automatically load the `nu-nix` module in every Nushell session via
      the vendor autoload mechanism.

      When enabled, a file is installed to
      `share/nushell/vendor/autoload/nu-nix.nu` which Nushell sources at
      startup, making all `nu-nix` commands, `from nix`, and `to nix`
      available without any manual `use nu-nix *`.

      When disabled, the module files are still installed; users can load
      them manually with a full path:
      `use ${cfg.package}/share/nushell/nu-nix *`
    '';
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = [
          pkgs.nushell
          cfg.package
        ];

        # Make the module and vendor autoload files visible in the system
        # profile, which Nushell searches via XDG_DATA_DIRS.
        environment.pathsToLink = [ "/share/nushell" ];

        # Register nu-bash as a valid login shell.
        environment.shells = [
          "${cfg.package}/bin/nu-bash"
          pkgs.bashInteractive
        ];
      }

      (lib.mkIf cfg.autoLoad {
        # Install a vendor autoload file so Nushell sources the module
        # automatically at startup — no `use nu-nix *` needed at all.
        environment.systemPackages = [
          (pkgs.runCommand "nu-nix-autoload" { } ''
            mkdir -p $out/share/nushell/vendor/autoload
            echo "use ${cfg.package}/share/nushell/nu-nix *" \
              > $out/share/nushell/vendor/autoload/nu-nix.nu
          '')
        ];
      })
    ]
  );
}
