{
  lib,
  nix,
  pkg-config,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "nu-plugin-nix";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;
  nativeBuildInputs = [
    pkg-config
    rustPlatform.bindgenHook
  ];
  buildInputs = [ nix.dev ];
  meta = {
    description = "Nushell plugin backed directly by the Nix C API";
    license = lib.licenses.mit;
    mainProgram = "nu_plugin_nix";
    platforms = lib.platforms.linux;
  };
}
