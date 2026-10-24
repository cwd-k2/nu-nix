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

    loginShellPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../packages/nu-nix-bash.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../packages/nu-nix-bash.nix { }";
      description = ''
        The optional nu-nix-bash compatibility launcher registered as a valid
        login shell. Set users.users.<name>.shell to this package to use it.
      '';
    };

    autoLoad = lib.mkEnableOption ''
      Automatically load the `nu-nix` module in every Nushell session via
      the vendor autoload mechanism.

      When enabled, a file is installed to
      `share/nushell/vendor/autoload/nu-nix.nu` which Nushell sources at
      startup, making the unified `nix` command family available without any
      manual `use nu-nix *`.

      When disabled, the module files are still installed; users can load
      them manually with the packaged plugin registry and module:
      `plugin use --plugin-config ${cfg.package}/share/nushell/nu-nix/plugin.msgpackz nix`
      `use ${cfg.package}/share/nushell/nu-nix *`
    '';
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment = {
          systemPackages = [
            pkgs.nushell
            cfg.package
          ];

          # Make the module and vendor autoload files visible in the system
          # profile, which Nushell searches via XDG_DATA_DIRS.
          pathsToLink = [ "/share/nushell" ];

          # Register nu-nix-bash as a valid login shell.
          shells = [
            cfg.loginShellPackage
            pkgs.bashInteractive
          ];
        };
      }

      (lib.mkIf cfg.autoLoad {
        # Install a vendor autoload file so Nushell sources the module
        # automatically at startup — no `use nu-nix *` needed at all.
        environment.systemPackages = [
          (pkgs.runCommand "nu-nix-autoload" { } ''
            mkdir -p $out/share/nushell/vendor/autoload
            cat > $out/share/nushell/vendor/autoload/nu-nix.nu <<'EOF'
            plugin use --plugin-config ${cfg.package}/share/nushell/nu-nix/plugin.msgpackz nix
            use ${cfg.package}/share/nushell/nu-nix *
            EOF
          '')
        ];
      })
    ]
  );
}
