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

      # Category display labels, in order of appearance.
      const CATEGORIES = [
        {key: "entry"   label: "Nushell entry points"}
        {key: "json"    label: "Structured output (JSON → nu table)"}
        {key: "legacy"  label: "Legacy nix-* wrappers"}
      ]

      # Single source of truth for commands: drives both usage and examples.
      const COMMANDS = [
        {cat: "entry"   cmd: "develop"          args: "[nix develop args...]"        desc: "Enter dev shell with Nushell"          example: "nu-nix develop .#default"}
        {cat: "entry"   cmd: "shell"            args: "[nix shell args...]"          desc: "Enter nix shell with Nushell"          example: "nu-nix shell nixpkgs#jq"}
        {cat: "entry"   cmd: "nix-shell"        args: "[nix-shell args...]"          desc: "Enter legacy nix-shell with Nushell"   example: "nu-nix nix-shell -p jq ripgrep"}
        {cat: "json"    cmd: "build"            args: "[args...]"                    desc: "Build; return output paths as table"   example: "nu-nix build"}
        {cat: "json"    cmd: "search"           args: "<registry> <query> [args...]" desc: "Search packages"                       example: "nu-nix search nixpkgs jq"}
        {cat: "json"    cmd: "path-info"        args: "<path> [args...]"             desc: "Query store path info"                 example: null}
        {cat: "json"    cmd: "print-dev-env"    args: "[args...]"                    desc: "Show dev environment variables"        example: "nu-nix print-dev-env"}
        {cat: "json"    cmd: "why-depends"      args: "<from> <to> [args...]"        desc: "Show dependency chain"                 example: null}
        {cat: "json"    cmd: "flake show"       args: "[args...]"                    desc: "Show flake outputs as table"           example: "nu-nix flake show"}
        {cat: "json"    cmd: "flake metadata"   args: "[args...]"                    desc: "Show flake metadata"                   example: "nu-nix flake metadata"}
        {cat: "json"    cmd: "derivation show"  args: "[args...]"                    desc: "Show derivation details"               example: null}
        {cat: "json"    cmd: "profile list"     args: "[args...]"                    desc: "List profile packages"                 example: null}
        {cat: "legacy"  cmd: "nix-build"        args: "[nix-build args...]"          desc: "Build; return paths as list"           example: "nu-nix nix-build -A hello"}
      ]

      # --- Nushell entry points ---

      def --wrapped "main develop" [...rest: string] {
        exec ${nix}/bin/nix develop ...$rest --command ${nushell}/bin/nu
      }

      def --wrapped "main shell" [...rest: string] {
        exec ${nix}/bin/nix shell ...$rest --command ${nushell}/bin/nu
      }

      def --wrapped "main nix-shell" [...rest: string] {
        exec ${nix}/bin/nix-shell ...$rest --run ${nushell}/bin/nu
      }

      # --- Structured output (JSON → nu table) ---

      def --wrapped "main build" [...rest: string] {
        ${nix}/bin/nix build --json ...$rest
        | from json
        | each {|r|
            $r.outputs
            | transpose output path
            | insert drvPath $r.drvPath
          }
        | flatten
      }

      def flake-description [info: any] {
        if ($info | describe | str starts-with "record") { $info.description? | default "" } else { "" }
      }

      def --wrapped "main flake show" [...rest: string] {
        # nix flake show --json has three distinct output shapes:
        #   named:      type → system → name  → info   (packages, devShells, apps, checks, …)
        #   per-system: type → system → info            (formatter)
        #   global:     type → name   → info            (nixosModules, overlays, …)
        let named_types = ["packages" "devShells" "apps" "checks" "legacyPackages"]

        ${nix}/bin/nix flake show --json ...$rest
        | from json
        | transpose type_name type_content
        | each {|row|
            let is_system_indexed = (
              $row.type_content | columns | any {|k| $k =~ 'linux|darwin|freebsd|netbsd|openbsd'}
            )
            if $is_system_indexed and ($row.type_name in $named_types) {
              # type → system → name → info
              $row.type_content | transpose system outputs
              | each {|s|
                  $s.outputs | transpose name info
                  | each {|n| {type: $row.type_name  system: $s.system  name: $n.name  description: (flake-description $n.info)}}
                }
              | flatten
            } else if $is_system_indexed {
              # type → system → info  (e.g. formatter)
              $row.type_content | transpose system info
              | each {|s| {type: $row.type_name  system: $s.system  name: null  description: (flake-description $s.info)}}
            } else {
              # type → name → info  (e.g. nixosModules, overlays)
              $row.type_content | transpose name info
              | each {|n| {type: $row.type_name  system: null  name: $n.name  description: (flake-description $n.info)}}
            }
          }
        | flatten
      }

      def --wrapped "main flake metadata" [...rest: string] {
        ${nix}/bin/nix flake metadata --json ...$rest | from json
      }

      def --wrapped "main search" [...rest: string] {
        ${nix}/bin/nix search --json ...$rest
        | from json
        | transpose attr info
        | each {|r| $r.info | insert attr $r.attr }
        | select attr pname version description
      }

      def --wrapped "main path-info" [...rest: string] {
        ${nix}/bin/nix path-info --json ...$rest
        | from json
        | transpose path info
        | each {|r| $r.info | insert path $r.path }
      }

      def --wrapped "main print-dev-env" [...rest: string] {
        ${nix}/bin/nix print-dev-env --json ...$rest
        | from json
        | get variables
        | transpose name info
        | each {|r| $r.info | insert name $r.name }
      }

      def --wrapped "main derivation show" [...rest: string] {
        ${nix}/bin/nix derivation show ...$rest
        | from json
        | transpose drv info
        | each {|r| $r.info | insert drv $r.drv }
      }

      def --wrapped "main profile list" [...rest: string] {
        ${nix}/bin/nix profile list --json ...$rest
        | from json
        | get elements
        | transpose name info
        | each {|r| $r.info | insert name $r.name }
      }

      def --wrapped "main why-depends" [...rest: string] {
        ${nix}/bin/nix why-depends --json ...$rest | from json
      }

      # --- Legacy nix-* wrappers ---

      def --wrapped "main nix-build" [...rest: string] {
        ${nix}/bin/nix-build ...$rest | lines
      }

      # --- Dispatch ---

      def usage [] {
        let prefix = "    nu-nix "
        let col_w = (
          $COMMANDS | get cmd
          | each {|c| ($prefix | str length) + ($c | str length) }
          | math max
        ) + 2

        print "Usage:"
        for $cat in $CATEGORIES {
          print $"  ($cat.label):"
          for $c in ($COMMANDS | where cat == $cat.key) {
            let label = ($"($prefix)($c.cmd)" | fill -w $col_w)
            print $"($label)($c.args)"
          }
          print ""
        }

        print "  Fallback (unknown subcommands pass through):"
        print $"($prefix)<nix-*> ...   →  exec nix-<cmd>"
        print $"($prefix)<cmd>   ...   →  exec nix <cmd>"
        print ""

        let examples = $COMMANDS | where example != null | get example
        if ($examples | is-not-empty) {
          print "Examples:"
          for $e in $examples {
            print $"  ($e)"
          }
        }
      }

      def --wrapped main [...args: string] {
        let subcommand = ($args | first | default "")
        let rest = ($args | skip 1)

        match $subcommand {
          "" | "-h" | "--help" | "help" => {
            usage
            exit 0
          }
          _ => {
            if ($subcommand | str starts-with "nix-") {
              let bin = $"${nix}/bin/($subcommand)"
              exec $bin ...$rest
            } else {
              exec ${nix}/bin/nix $subcommand ...$rest
            }
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
