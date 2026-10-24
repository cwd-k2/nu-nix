{
  callPackage,
  lib,
  writeTextDir,
}:

{
  name,
  variables ? { },
  prependPath ? { },
  appendPath ? { },
  autoLoad ? false,
  meta ? { },
  passthru ? { },
}:

let
  renderNuValue = import ./render-nu-value.nix { inherit lib; };
  variableNames = lib.attrNames variables ++ lib.attrNames prependPath ++ lib.attrNames appendPath;
  invalidVariableNames = builtins.filter (
    variable: builtins.match "[A-Za-z_][A-Za-z0-9_]*" variable == null
  ) variableNames;
  pathNames = lib.unique (lib.attrNames prependPath ++ lib.attrNames appendPath);
  invalidPathValues = builtins.filter (
    variable:
    let
      value =
        if builtins.hasAttr variable prependPath then
          builtins.getAttr variable prependPath
        else
          builtins.getAttr variable appendPath;
    in
    !builtins.isList value
  ) pathNames;
  invalidPathEntries = builtins.filter (
    variable:
    let
      value =
        if builtins.hasAttr variable prependPath then
          builtins.getAttr variable prependPath
        else
          builtins.getAttr variable appendPath;
    in
    builtins.isList value && !(lib.all (entry: builtins.isString entry || builtins.isPath entry) value)
  ) pathNames;
  duplicateOperations = builtins.filter (
    variable: builtins.hasAttr variable prependPath && builtins.hasAttr variable appendPath
  ) pathNames;
  renderPathOperation =
    operation: variable: entries:
    let
      current = "($env | get --optional ${builtins.toJSON variable} | default [])";
      requested = renderNuValue entries;
      remaining = "(${current} | where {|entry| $entry not-in ${requested}})";
      result =
        if operation == "prepend" then
          "(${requested} | uniq | append ${remaining})"
        else
          "(${remaining} | append (${requested} | uniq))";
    in
    "load-env {${builtins.toJSON variable}: ${result}}";
  source = ''
    export-env {
      load-env ${renderNuValue variables}
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (renderPathOperation "prepend") prependPath)}
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (renderPathOperation "append") appendPath)}
    }
  '';
  mkNuModule = callPackage ./mk-nu-module.nix { };
in
assert lib.assertMsg (invalidVariableNames == [ ])
  "Nushell environment variable names must use shell-compatible identifiers; invalid names: ${lib.concatStringsSep ", " invalidVariableNames}";
assert lib.assertMsg (invalidPathValues == [ ])
  "Nushell PATH operations require lists; invalid variables: ${lib.concatStringsSep ", " invalidPathValues}";
assert lib.assertMsg (invalidPathEntries == [ ])
  "Nushell PATH operation entries must be strings or paths; invalid variables: ${lib.concatStringsSep ", " invalidPathEntries}";
assert lib.assertMsg (duplicateOperations == [ ])
  "A Nushell environment variable cannot have both prependPath and appendPath operations: ${lib.concatStringsSep ", " duplicateOperations}";
mkNuModule {
  inherit
    autoLoad
    meta
    name
    passthru
    ;
  src = writeTextDir "mod.nu" source;
}
