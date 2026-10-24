{
  callPackage,
  lib,
  writeTextDir,
}:

{
  name,
  values,
  autoLoad ? false,
  meta ? { },
  passthru ? { },
}:

let
  support = import ./builder-support.nix { inherit lib; };
  renderNuValue = import ./render-nu-value.nix { inherit lib; };
  invalidIdentifiers = builtins.filter (name': !support.validNuIdentifier name') (
    lib.attrNames values
  );
  source = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (exportName: value: "export const ${exportName} = ${renderNuValue value}") values
  );
  mkNuModule = callPackage ./mk-nu-module.nix { };
in
assert lib.assertMsg (invalidIdentifiers == [ ])
  "Nushell export names must be non-reserved identifiers containing only letters, digits, or underscores; invalid names: ${lib.concatStringsSep ", " invalidIdentifiers}";
mkNuModule {
  inherit
    autoLoad
    meta
    name
    passthru
    ;
  src = writeTextDir "mod.nu" "${source}\n";
}
