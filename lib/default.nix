{ self }:

{
  mkNuModule =
    { pkgs, ... }@args:
    let
      builder = pkgs.callPackage ./mk-nu-module.nix { };
    in
    builder (builtins.removeAttrs args [ "pkgs" ]);

  mkNuApplication =
    { pkgs, ... }@args:
    let
      system = pkgs.stdenv.hostPlatform.system;
      builder = pkgs.callPackage ./mk-nu-application.nix {
        nuNixPackage = self.packages.${system}.default;
      };
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
    { pkgs, ... }@args:
    let
      system = pkgs.stdenv.hostPlatform.system;
      builder = pkgs.callPackage ./run-nu-command.nix {
        nuNixPackage = self.packages.${system}.default;
      };
    in
    builder (builtins.removeAttrs args [ "pkgs" ]);
}
