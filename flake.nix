{
  description = "Nushell and Nix integration helpers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-parts,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      lib = import ./nix/lib { inherit self; };

      packages = forAllSystems (pkgs: {
        default = pkgs.callPackage ./nix/packages/nu-nix.nix { };
        nu-nix = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        native-plugin = pkgs.callPackage ./crates/nu-plugin-nix { };
        nu-nix-bash = pkgs.callPackage ./nix/packages/nu-nix-bash.nix { };
      });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.nu-nix-bash}/bin/nu-nix-bash";
          meta.description = "Launch Nushell via the nu-nix-bash login-shell wrapper";
        };
        nu-nix-bash = self.apps.${pkgs.stdenv.hostPlatform.system}.default;
      });

      nixosModules.default = import ./nix/modules/nixos.nix;
      nixosModules.nu-nix = self.nixosModules.default;
      homeManagerModules.default = import ./nix/modules/home-manager.nix;
      homeManagerModules.nu-nix = self.homeManagerModules.default;
      flakeModules.default = import ./nix/flake-module.nix;
      flakeModules.nu-nix = self.flakeModules.default;

      checks = forAllSystems (
        pkgs:
        import ./tests/nix {
          inherit
            self
            nixpkgs
            flake-parts
            pkgs
            ;
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          inputsFrom = [ self.packages.${pkgs.stdenv.hostPlatform.system}.native-plugin ];
          packages = [
            pkgs.cargo
            pkgs.clippy
            pkgs.rustc
            pkgs.rustfmt
          ];
        };
      });
    };
}
