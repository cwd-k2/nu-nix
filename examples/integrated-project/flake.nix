{
  description = "An integrated Nix and Nushell project using nu-nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.follows = "nu-nix/flake-parts";
    nu-nix = {
      url = "path:../..";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      nu-nix,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ nu-nix.flakeModules.default ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        { pkgs, ... }:
        let
          example = import ./default.nix { inherit pkgs nu-nix; };
        in
        {
          inherit (example) tasks;
          packages = {
            default = example.application;
            session = example.nuSession;
          };
          apps = {
            default = {
              type = "app";
              program = pkgs.lib.getExe example.application;
              meta.description = "Run the generated Nushell application";
            };
            session = {
              type = "app";
              program = pkgs.lib.getExe example.nuSession;
              meta.description = "Start the composed Nushell session";
            };
          };

          nushell = {
            inherit (example.published) modules applications plugins;
            exports.describe = nu-nix.lib.mkNuExport {
              inherit pkgs;
              description = "Build a small project description from Nix data";
              arguments = [ "name" ];
              result = "collect";
              function = name: {
                inherit name;
                host = "example-host";
                features = [
                  "generated-data"
                  "generated-environment"
                ];
              };
            };
          };
        };
    };
}
