{ lib }:

let
  validPathComponent = component: builtins.match "[A-Za-z0-9][A-Za-z0-9._+-]*" component != null;
in
{
  validName = validPathComponent;

  validEnvironmentName = name: builtins.match "[A-Za-z_][A-Za-z0-9_]*" name != null;

  validNuIdentifier =
    name:
    builtins.match "[A-Za-z_][A-Za-z0-9_]*" name != null
    && !(builtins.elem name [
      "env"
      "in"
      "nu"
    ]);

  validEnvironmentValue =
    value: builtins.isString value || builtins.isPath value || lib.isDerivation value;

  validRelativePath =
    path: builtins.isString path && path != "" && lib.all validPathComponent (lib.splitString "/" path);

  mkNuLibraryPath =
    {
      nuLibraries,
      nuLibDirs,
    }:
    let
      recordSeparator = builtins.fromJSON ''"\u001e"'';
      directories = map (package: "${package}/share/nushell") nuLibraries ++ nuLibDirs;
    in
    if directories == [ ] then null else lib.concatStringsSep recordSeparator directories;
}
