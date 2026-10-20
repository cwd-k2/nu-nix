{
  lib,
  runCommand,
}:

{
  name,
  src,
  autoLoad ? false,
  meta ? { },
  passthru ? { },
}:

let
  support = import ./builder-support.nix { inherit lib; };
in
assert lib.assertMsg (support.validName name)
  "Nushell module names must be safe path basenames; invalid name: ${builtins.toJSON name}";
runCommand "${name}-nu-module"
  {
    inherit meta passthru;
  }
  ''
    module_directory="$out/share/nushell/${name}"
    mkdir -p "$module_directory"
    cp -R ${src}/. "$module_directory/"

    if [[ ! -f "$module_directory/mod.nu" ]]; then
      echo "Nushell module ${name} does not provide mod.nu" >&2
      exit 1
    fi

    ${
      if autoLoad then
        ''
          autoload="$out/share/nushell/vendor/autoload/${name}.nu"
          mkdir -p "$(dirname "$autoload")"
          printf 'use %s *\n' "$module_directory" > "$autoload"
        ''
      else
        ""
    }
  ''
