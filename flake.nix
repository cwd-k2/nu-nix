{
  description = "Nushell and Nix integration helpers";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.callPackage ./package { };
        nu-nix = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        with-autoload = pkgs.callPackage ./package { withAutoload = true; };
      });

      apps = forAllSystems (pkgs: {
        # `nix run github:cwd-k2/nu-nix` launches Nushell via the nu-bash wrapper.
        default = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/nu-bash";
          meta.description = "Launch Nushell via the nu-bash login-shell wrapper";
        };
      });

      nixosModules.default = import ./modules/nu-nix.nix;
      nixosModules.nu-nix = self.nixosModules.default;
      homeManagerModules.default = import ./modules/home-manager.nix;
      homeManagerModules.nu-nix = self.homeManagerModules.default;

      checks = forAllSystems (
        pkgs:
        let
          system = pkgs.stdenv.hostPlatform.system;
          pkg = self.packages.${system}.default;
          pkgWithAutoload = self.packages.${system}.with-autoload;
          testSystem = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              {
                programs.nu-nix.enable = true;
                programs.nu-nix.autoLoad = true;
                system.stateVersion = "26.05";
              }
            ];
          };
          testSystemNoAutoload = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              {
                programs.nu-nix.enable = true;
                programs.nu-nix.autoLoad = false;
                system.stateVersion = "26.05";
              }
            ];
          };
          testHome = pkgs.lib.evalModules {
            specialArgs = { inherit pkgs; };
            modules = [
              {
                options.home.packages = pkgs.lib.mkOption {
                  type = pkgs.lib.types.listOf pkgs.lib.types.package;
                  default = [ ];
                };
                options.xdg.configFile = pkgs.lib.mkOption {
                  type = pkgs.lib.types.attrs;
                  default = { };
                };
              }
              self.homeManagerModules.default
              {
                programs.nu-nix.enable = true;
                programs.nu-nix.autoLoad = true;
              }
            ];
          };
        in
        {
          package = pkg;

          package-with-autoload = pkgWithAutoload;

          package-autoload-shape = pkgs.runCommand "nu-nix-package-autoload-shape-test" { } ''
            test -d ${pkg}/share/nushell/nu-nix
            test ! -e ${pkg}/share/nushell/vendor/autoload/nu-nix.nu
            test -f ${pkgWithAutoload}/share/nushell/vendor/autoload/nu-nix.nu
            grep -F '/share/nushell/nu-nix' \
              ${pkgWithAutoload}/share/nushell/vendor/autoload/nu-nix.nu
            touch $out
          '';

          nixos-autoload = pkgs.runCommand "nu-nix-nixos-autoload-test" { } ''
            test -f ${testSystem.config.system.path}/share/nushell/vendor/autoload/nu-nix.nu
            grep -F '${pkg}/share/nushell/nu-nix' \
              ${testSystem.config.system.path}/share/nushell/vendor/autoload/nu-nix.nu
            touch $out
          '';

          nixos-no-autoload = pkgs.runCommand "nu-nix-nixos-no-autoload-test" { } ''
            test -d ${testSystemNoAutoload.config.system.path}/share/nushell/nu-nix
            test ! -e ${testSystemNoAutoload.config.system.path}/share/nushell/vendor/autoload/nu-nix.nu
            touch $out
          '';

          home-manager-autoload = pkgs.runCommand "nu-nix-home-manager-autoload-test" { } ''
            test ${builtins.toString (builtins.elem pkg testHome.config.home.packages)} = 1
            test ${builtins.toString (builtins.elem pkgs.nushell testHome.config.home.packages)} = 1
            test ${
              builtins.toString (
                testHome.config.xdg.configFile."nushell/autoload/nu-nix.nu".text
                == "use ${pkg}/share/nushell/nu-nix *\n"
              )
            } = 1
            touch $out
          '';

          # Pure Nushell tests for `to nix` — no Nix evaluation, runs in sandbox.
          to-nix-tests = pkgs.runCommand "nu-nix-to-nix-tests" { buildInputs = [ pkgs.nushell ]; } ''
            cp ${./tests/test_to_nix.nu} test_to_nix.nu
            substituteInPlace test_to_nix.nu \
              --replace '../package/scripts/nu-nix/mod.nu' \
                        '${pkg}/share/nushell/nu-nix/mod.nu'
            nu test_to_nix.nu
            touch $out
          '';
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
