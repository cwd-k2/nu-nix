{ config, lib, pkgs, ... }:

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
        The nu-nix package.  Provides <literal>nu-bash</literal> (login-shell
        wrapper) and the <literal>nu-nix</literal> Nushell module under
        <literal>share/nushell/nu-nix/</literal>.
      '';
    };

    autoLoad = lib.mkEnableOption ''
      Automatically load the <literal>nu-nix</literal> module in every
      Nushell session via the vendor autoload mechanism.

      When enabled, a file is installed to
      <literal>share/nushell/vendor/autoload/nu-nix.nu</literal> which
      Nushell sources at startup, making all <literal>nu-nix</literal>
      commands, <literal>from nix</literal>, and <literal>to nix</literal>
      available without any manual <literal>use nu-nix *</literal>.

      When disabled, the module files are still installed; users can load
      them manually:
      <literal>use ${cfg.package}/share/nushell/nu-nix *</literal>
    '';
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages = [ pkgs.nushell cfg.package ];

      # Register nu-bash as a valid login shell.
      environment.shells = [
        "${cfg.package}/bin/nu-bash"
        pkgs.bashInteractive
      ];

      # Add the module directory to NU_LIB_DIRS so that
      #   use nu-nix *
      # resolves by name without a full path.
      # Requires programs.nushell.enable = true.
      programs.nushell.extraConfig = ''
        $env.NU_LIB_DIRS = ($env.NU_LIB_DIRS? | default [] | append "${cfg.package}/share/nushell")
      '';
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
  ]);
}
