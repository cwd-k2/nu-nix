{
  bashInteractive,
  callPackage,
  lib,
  nushell,
  symlinkJoin,
  writeShellApplication,
}:

let
  mkNuModule = callPackage ../lib/mk-nu-module.nix { };
  nuBash = writeShellApplication {
    name = "nu-bash";
    text = ''
      bash="${bashInteractive}/bin/bash"
      nu="${nushell}/bin/nu"

      # Login-shell compatibility wrapper. Tools such as Zed, ssh, WSL
      # launchers, and nix may run the user's shell with POSIX snippets.
      # Keep those executions on bash.
      if [ "$#" -gt 0 ]; then
        exec "$bash" "$@"
      fi

      # Human interactive terminals get Nushell.
      if [ -t 0 ] && [ -t 1 ]; then
        exec "$nu"
      fi

      exec "$bash"
    '';
  };

  nuNixModule = mkNuModule {
    name = "nu-nix";
    src = ./scripts/nu-nix;
  };
in
symlinkJoin {
  name = "nu-nix";
  paths = [
    nuBash
    nuNixModule
  ];

  # Let NixOS treat this derivation as a login-shell package.  In particular,
  # users.users.<name>.shell can then point at the package and NixOS records
  # the stable /run/current-system/sw path in /etc/passwd.
  passthru.shellPath = "/bin/nu-bash";

  meta = {
    description = "Nushell and Nix integration: login-shell wrapper and nu-nix module";
    license = lib.licenses.mit;
    mainProgram = "nu-bash";
    platforms = lib.platforms.linux;
  };
}
