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
  plugins ? lib.optional (builtins.elem nuNixPackage nuLibraries) "${nuNixPackage}/bin/nu_plugin_nix",
  derivationArgs ? { },
}:

let
  support = import ./builder-support.nix { inherit lib; };
  resolvedScript = if scriptText != null then writeText "${name}.nu" scriptText else scriptFile;
  includePath = support.mkNuLibraryPath { inherit nuLibraries nuLibDirs; };
  validPlugin = plugin: builtins.isString plugin || builtins.isPath plugin;
  nuArgs = [
    "--no-config-file"
  ]
  ++ lib.optionals (includePath != null) [
    "--include-path"
    includePath
  ]
  ++ lib.concatMap (plugin: [
    "--plugins"
    plugin
  ]) plugins;
in
assert lib.assertMsg (support.validName name)
  "Nushell command derivation names must be safe path basenames; invalid name: ${builtins.toJSON name}";
assert lib.assertMsg (
  (scriptFile != null) != (scriptText != null)
) "Nushell commands require exactly one of scriptFile and scriptText";
assert lib.assertMsg (builtins.isList plugins) "Nushell command plugins must be a list";
assert lib.assertMsg (lib.all validPlugin plugins)
  "Nushell command plugins must be executable path strings";
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
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    exec ${lib.escapeShellArg (lib.getExe nushell)} ${lib.escapeShellArgs nuArgs} "$nuScript"
  ''
