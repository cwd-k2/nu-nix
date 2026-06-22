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
    text = ''
      #!${nushell}/bin/nu

      def usage [] {
        print "Usage:"
        print "  nu-nix develop [nix develop args...]"
        print "  nu-nix shell [nix shell args...]"
        print "  nu-nix nix-shell [nix-shell args...]"
        print ""
        print "Examples:"
        print "  nu-nix develop"
        print "  nu-nix develop .#default"
        print "  nu-nix shell nixpkgs#jq"
        print "  nu-nix nix-shell -p jq ripgrep"
      }

      def --wrapped main [...args: string] {
        let subcommand = ($args | first | default "")
        let rest = ($args | skip 1)

        match $subcommand {
          "develop" => {
            exec ${nix}/bin/nix develop ...$rest --command ${nushell}/bin/nu
          }
          "shell" => {
            exec ${nix}/bin/nix shell ...$rest --command ${nushell}/bin/nu
          }
          "nix-shell" => {
            exec ${nix}/bin/nix-shell ...$rest --run ${nushell}/bin/nu
          }
          "" | "-h" | "--help" | "help" => {
            usage
            exit 0
          }
          _ => {
            print --stderr $"nu-nix: unknown subcommand: ($subcommand)"
            print --stderr "Try: nu-nix --help"
            exit 2
          }
        }
      }
    '';
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
