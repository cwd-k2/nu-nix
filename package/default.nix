{
  bashInteractive,
  lib,
  nushell,
  runCommand,
  symlinkJoin,
  withAutoload ? false,
  writeShellApplication,
}:

let
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

  nuNixModule = runCommand "nu-nix-module" { } ''
    mkdir -p $out/share/nushell/nu-nix
    cp ${./scripts/nu-nix/mod.nu}          $out/share/nushell/nu-nix/mod.nu
    cp ${./scripts/nu-nix/commands.nu}     $out/share/nushell/nu-nix/commands.nu
    cp ${./scripts/nu-nix/from-nix.nu}     $out/share/nushell/nu-nix/from-nix.nu
    cp ${./scripts/nu-nix/to-nix.nu}       $out/share/nushell/nu-nix/to-nix.nu
    cp ${./scripts/nu-nix/legacy.nu}       $out/share/nushell/nu-nix/legacy.nu
  '';

  nuNixAutoload = runCommand "nu-nix-autoload" { } ''
    mkdir -p $out/share/nushell/vendor/autoload
    echo "use ${nuNixModule}/share/nushell/nu-nix *" \
      > $out/share/nushell/vendor/autoload/nu-nix.nu
  '';
in
symlinkJoin {
  name = if withAutoload then "nu-nix-with-autoload" else "nu-nix";
  paths = [
    nuBash
    nuNixModule
  ]
  ++ lib.optional withAutoload nuNixAutoload;

  meta = {
    description = "Nushell and Nix integration: login-shell wrapper and nu-nix module";
    license = lib.licenses.mit;
    mainProgram = "nu-bash";
    platforms = lib.platforms.linux;
  };
}
