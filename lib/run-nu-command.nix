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
  recordSeparator = builtins.fromJSON ''"\u001e"'';
  libraryDirectories = map (package: "${package}/share/nushell") nuLibraries ++ nuLibDirs;
  nuArgs = [
    "--no-config-file"
  ]
  ++ lib.optionals (libraryDirectories != [ ]) [
    "--include-path"
    (lib.concatStringsSep recordSeparator libraryDirectories)
  ];
in
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
