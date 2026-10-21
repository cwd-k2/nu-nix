{
  lib,
  nuNixPackage,
  nushell,
  runCommand,
  writeText,
}:

{
  name,
  script ? null,
  scriptFile ? null,
  scriptText ? null,
  runtimeInputs ? [ ],
  nuLibraries ? [ nuNixPackage ],
  nuLibDirs ? [ ],
  derivationArgs ? { },
}:

let
  support = import ./builder-support.nix { inherit lib; };
  fileScripts = builtins.filter (candidate: candidate != null) [
    script
    scriptFile
  ];
  resolvedScript =
    if scriptText != null then writeText "${name}.nu" scriptText else builtins.head fileScripts;
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
  (builtins.length fileScripts == 1) != (scriptText != null)
) "Nushell commands require exactly one of scriptFile (or its script alias) and scriptText";
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
