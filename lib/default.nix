_:

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
      nuNixPackage ? pkgs.callPackage ../package { },
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
      nuNixPackage ? pkgs.callPackage ../package { },
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
}
