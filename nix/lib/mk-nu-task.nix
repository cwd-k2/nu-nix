{ lib, ... }:

{
  script,
  description ? "",
  deps ? [ ],
  runtimeInputs ? [ ],
  environment ? { },
  sourceRoot ? null,
}:

let
  support = import ./task-support.nix { inherit lib; };
  capturedRoot = if sourceRoot == null then builtins.dirOf script else sourceRoot;
  scriptPath = toString script;
  rootPath = toString capturedRoot;
  entrypoint = lib.removePrefix "${rootPath}/" scriptPath;
  fileSource =
    if builtins.isPath script then
      builtins.path {
        path = capturedRoot;
        name = "nu-task-source";
      }
    else
      null;
in
assert lib.assertMsg (
  builtins.isPath script || builtins.isString script
) "Nushell task scripts must be paths or inline strings";
assert lib.assertMsg (
  builtins.isList runtimeInputs && lib.all lib.isDerivation runtimeInputs
) "Nushell task runtimeInputs must be derivations";
assert lib.assertMsg (builtins.isAttrs environment)
  "Nushell task environment must be an attribute set";
assert lib.assertMsg (
  sourceRoot == null || builtins.isPath sourceRoot
) "Nushell task sourceRoot must be a path";
assert lib.assertMsg (
  sourceRoot == null || builtins.isPath script
) "Nushell task sourceRoot is only valid for file scripts";
assert lib.assertMsg (
  !builtins.isPath script || lib.hasPrefix "${rootPath}/" scriptPath
) "Nushell task script must be contained by sourceRoot";
assert lib.assertMsg (
  !(environment ? PATH)
) "Nushell task environment.PATH is reserved; use runtimeInputs";
assert lib.assertMsg (lib.all (name: builtins.match "[A-Za-z_][A-Za-z0-9_]*" name != null) (
  lib.attrNames environment
)) "Nushell task environment names must be shell-compatible identifiers";
assert lib.assertMsg (lib.all (value: builtins.isString value || builtins.isPath value) (
  lib.attrValues environment
)) "Nushell task environment values must be strings or paths";
support.mkTask {
  inherit
    deps
    description
    ;
  action = {
    type = "nushell";
    environment = lib.mapAttrs (_: toString) environment;
    script =
      if builtins.isPath script then
        {
          type = "file";
          path = "${fileSource}/${entrypoint}";
        }
      else
        {
          type = "inline";
          text = script;
        };
    path = lib.makeBinPath runtimeInputs;
  };
}
