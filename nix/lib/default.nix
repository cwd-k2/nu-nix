_:

let
  callPureBuilder =
    path:
    {
      lib ? null,
      pkgs ? null,
      ...
    }@args:
    let
      selectedLib = if lib != null then lib else pkgs.lib;
      builder = import path { lib = selectedLib; };
    in
    assert lib != null || pkgs != null;
    builder (
      builtins.removeAttrs args [
        "lib"
        "pkgs"
      ]
    );
in

{
  mkNuModule =
    { pkgs, ... }@args:
    let
      builder = pkgs.callPackage ./mk-nu-module.nix { };
    in
    builder (builtins.removeAttrs args [ "pkgs" ]);

  mkNuApplication =
    {
      pkgs,
      nuNixPackage ? pkgs.callPackage ../packages/nu-nix.nix { },
      ...
    }@args:
    let
      builder = pkgs.callPackage ./mk-nu-application.nix { inherit nuNixPackage; };
    in
    builder (
      builtins.removeAttrs args [
        "pkgs"
        "nuNixPackage"
      ]
    );

  mkNuSession =
    { pkgs, ... }@args:
    let
      builder = pkgs.callPackage ./mk-nu-session.nix { };
    in
    builder (builtins.removeAttrs args [ "pkgs" ]);

  mkNuModuleFromValue =
    { pkgs, ... }@args:
    let
      builder = pkgs.callPackage ./mk-nu-module-from-value.nix { };
    in
    builder (builtins.removeAttrs args [ "pkgs" ]);

  mkNuEnvModule =
    { pkgs, ... }@args:
    let
      builder = pkgs.callPackage ./mk-nu-env-module.nix { };
    in
    builder (builtins.removeAttrs args [ "pkgs" ]);

  runNuCommand =
    {
      pkgs,
      nuNixPackage ? pkgs.callPackage ../packages/nu-nix.nix { },
      ...
    }@args:
    let
      builder = pkgs.callPackage ./run-nu-command.nix { inherit nuNixPackage; };
    in
    builder (
      builtins.removeAttrs args [
        "pkgs"
        "nuNixPackage"
      ]
    );

  mkNuTask =
    { pkgs, ... }@args:
    let
      builder = pkgs.callPackage ./mk-nu-task.nix { };
    in
    builder (builtins.removeAttrs args [ "pkgs" ]);

  mkDerivationTask = callPureBuilder ./mk-derivation-task.nix;

  mkNuExport = callPureBuilder ./mk-nu-export.nix;
}
