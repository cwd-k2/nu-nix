{
  callPackage,
  lib,
  nativePlugin ? callPackage ../../crates/nu-plugin-nix { },
  nushell,
  runCommand,
  symlinkJoin,
}:

let
  mkNuModule = callPackage ../lib/mk-nu-module.nix { };
  nuNixModule = mkNuModule {
    name = "nu-nix";
    src = ../../nushell/nu-nix;
  };

  pluginRegistry = runCommand "nu-nix-plugin-registry" { nativeBuildInputs = [ nushell ]; } ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME" "$out/share/nushell/nu-nix"
    nu --no-config-file --commands \
      "plugin add --plugin-config '$out/share/nushell/nu-nix/plugin.msgpackz' '${nativePlugin}/bin/nu_plugin_nix'"
  '';
in
symlinkJoin {
  name = "nu-nix";
  paths = [
    nuNixModule
    nativePlugin
    pluginRegistry
  ];

  meta = {
    description = "Native Nushell and Nix integration";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
