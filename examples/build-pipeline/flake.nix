{
  description = "A Nushell-authored build and publication pipeline using nu-nix";

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
          project = import ./default.nix { inherit pkgs nu-nix; };
        in
        {
          inherit (project) tasks;
          packages.default = project.report;

          nushell = {
            modules.catalog = {
              package = project.catalogModule;
              entrypoint = "share/nushell/project-catalog/mod.nu";
              description = "Nix-generated catalog used by the report build";
            };
            modules.report-tools = {
              package = project.reportModule;
              entrypoint = "share/nushell/report-tools/mod.nu";
              description = "Reusable report construction commands";
            };
            exports.select-item = nu-nix.lib.mkNuExport {
              inherit pkgs;
              description = "Select one catalog item by name";
              arguments = [ "name" ];
              result = "collect";
              function = project.selectItem;
            };
          };
        };
    };
}
