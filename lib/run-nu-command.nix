{
  lib,
  nuNixPackage,
  nushell,
  runCommand,
}:

{
  name,
  script,
  runtimeInputs ? [ ],
  nuLibraries ? [ nuNixPackage ],
  nuLibDirs ? [ ],
  derivationArgs ? { },
}:

let
  support = import ./builder-support.nix { inherit lib; };
  includePath = support.mkNuLibraryPath { inherit nuLibraries nuLibDirs; };
  nuArgs = [
    "--no-config-file"
  ]
  ++ lib.optionals (includePath != null) [
    "--include-path"
    includePath
  ];
in
assert lib.assertMsg (support.validName name)
  "Nushell command derivation names must be safe path basenames; invalid name: ${builtins.toJSON name}";
assert lib.assertMsg (
  builtins.isPath script || builtins.isString script
) "Nushell command scripts must be paths or strings";
runCommand name
  (
    derivationArgs
    // {
      nativeBuildInputs = (derivationArgs.nativeBuildInputs or [ ]) ++ runtimeInputs;
      nuScript = script;
    }
  )
  ''
    exec ${lib.getExe nushell} ${lib.escapeShellArgs nuArgs} "$nuScript"
  ''
