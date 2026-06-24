{
  bashInteractive,
  lib,
  nix,
  nushell,
  symlinkJoin,
  writeShellApplication,
  writeTextFile,
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

  nuNix = writeTextFile {
    name = "nu-nix";
    destination = "/bin/nu-nix";
    executable = true;
    text = builtins.replaceStrings
      [ "@nix@"     "@nushell@"     ]
      [ "${nix}"    "${nushell}"    ]
      (builtins.readFile ./scripts/nu-nix.nu);
  };
in
symlinkJoin {
  name = "nu-nix";
  paths = [
    nuBash
    nuNix
  ];

  meta = {
    description = "Small Nushell and Nix integration helpers";
    license = lib.licenses.mit;
    mainProgram = "nu-nix";
    platforms = lib.platforms.linux;
  };
}
