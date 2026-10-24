{
  lib,
  nuNixPackage,
  nushell,
  runCommand,
  writeText,
}:

{
  name,
  scriptFile ? null,
  scriptText ? null,
  runtimeInputs ? [ ],
  nuLibraries ? [ nuNixPackage ],
  nuLibDirs ? [ ],
  derivationArgs ? { },
}:

let
  support = import ./builder-support.nix { inherit lib; };
  resolvedScript = if scriptText != null then writeText "${name}.nu" scriptText else scriptFile;
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
  (scriptFile != null) != (scriptText != null)
) "Nushell commands require exactly one of scriptFile and scriptText";
assert lib.assertMsg (
  builtins.isPath resolvedScript
  || builtins.isString resolvedScript
  || lib.isDerivation resolvedScript
) "Nushell command scriptFile must be a path or string";
runCommand name
  (
    derivationArgs
    // {
      nativeBuildInputs = (derivationArgs.nativeBuildInputs or [ ]) ++ runtimeInputs;
      nuScript = resolvedScript;
    }
  )
  ''
    exec ${lib.escapeShellArg (lib.getExe nushell)} ${lib.escapeShellArgs nuArgs} "$nuScript"
  ''
