{ lib }:

{
  targets,
  description ? "",
  deps ? [ ],
}:

let
  support = import ./task-support.nix { inherit lib; };
in
assert lib.assertMsg (
  builtins.isAttrs targets && builtins.length (lib.attrNames targets) > 0
) "Derivation task targets must be a non-empty attribute set";
assert lib.assertMsg (lib.all (name: builtins.match "[A-Za-z_][A-Za-z0-9_-]*" name != null) (
  lib.attrNames targets
)) "Derivation task target names must be simple identifiers";
assert lib.assertMsg (lib.all lib.isDerivation (
  lib.attrValues targets
)) "Derivation task targets must be derivations";
support.mkTask {
  inherit
    deps
    description
    ;
  action = {
    type = "realise";
    targets = lib.mapAttrs (_: target: "${target}") targets;
  };
}
