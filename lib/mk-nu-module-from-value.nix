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
  renderNuValue = import ./render-nu-value.nix { inherit lib; };
  validIdentifier = name': builtins.match "[A-Za-z_][A-Za-z0-9_]*" name' != null;
  invalidIdentifiers = builtins.filter (name': !validIdentifier name') (lib.attrNames values);
  source = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (exportName: value: "export const ${exportName} = ${renderNuValue value}") values
  );
  mkNuModule = callPackage ./mk-nu-module.nix { };
in
assert lib.assertMsg (invalidIdentifiers == [ ])
  "Nushell export names must start with a letter or underscore and contain only letters, digits, or underscores; invalid names: ${lib.concatStringsSep ", " invalidIdentifiers}";
mkNuModule {
  inherit
    autoLoad
    meta
    name
    passthru
    ;
  src = writeTextDir "mod.nu" "${source}\n";
}
