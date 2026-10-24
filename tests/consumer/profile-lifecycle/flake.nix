{
  inputs.nu-nix.url = "path:__NU_NIX_SOURCE__";
  inputs.nixpkgs.follows = "nu-nix/nixpkgs";

  outputs =
    { nixpkgs, nu-nix, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          version = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile ./version);
          demo = pkgs.writeShellScriptBin "demo" ''
            printf '%s\n' ${pkgs.lib.escapeShellArg version}
          '';
        in
        {
          default = nu-nix.lib.mkNuSession {
            inherit pkgs;
            name = "lifecycle-session";
            applications.demo = {
              package = demo;
              entrypoint = "bin/demo";
            };
          };
        }
      );
    };
}
