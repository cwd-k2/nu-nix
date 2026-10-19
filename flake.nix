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
      lib = import ./lib { inherit self; };

      packages = forAllSystems (pkgs: {
        default = pkgs.callPackage ./package { };
        nu-nix = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        with-autoload = pkgs.callPackage ./package {
          withAutoload = true;
        };
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
          generatedApplicationExample = import ./examples/generated-application/default.nix {
            inherit pkgs;
            nu-nix = self;
          };
          bareApplication = self.lib.mkNuApplication {
            inherit pkgs;
            name = "nu-nix-bare-application-test";
            src = ./tests/bare-application;
            nuLibraries = [ ];
            environment.NU_NIX_BARE_TEST = "without-libraries";
          };
          generatedValueModule = self.lib.mkNuModuleFromValue {
            inherit pkgs;
            name = "generated-values";
            values = {
              answer = 42;
              empty = { };
              nested = {
                enabled = true;
                items = [
                  ''quoted "value"''
                  "line\nbreak"
                  null
                ];
              };
            };
          };
          generatedEnvModule = self.lib.mkNuEnvModule {
            inherit pkgs;
            name = "generated-env";
            autoLoad = true;
            variables = {
              NU_NIX_GENERATED = "configured";
              NU_NIX_TYPED = [
                1
                2
                3
              ];
              NU_NIX_TEST_PATH = [
                "/existing"
                "/shared"
              ];
              NU_NIX_APPEND_PATH = [
                "/existing"
                "/shared"
              ];
            };
            prependPath.NU_NIX_TEST_PATH = [
              "/first"
              "/shared"
            ];
            appendPath.NU_NIX_APPEND_PATH = [
              "/shared"
              "/last"
            ];
          };
          testSystem = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              ({ config, ... }: {
                programs.nu-nix.enable = true;
                programs.nu-nix.autoLoad = true;
                users.users.nu-nix-test = {
                  isNormalUser = true;
                  shell = config.programs.nu-nix.package;
                };
                system.stateVersion = "26.05";
              })
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

          application = pkgs.runCommand "nu-nix-application-test-result" { } ''
            output=$(${generatedApplicationExample.application}/bin/nu-nix-generated-example tester)
            printf '%s\n' "$output" | grep -F '"greeting":"hello tester"'
            printf '%s\n' "$output" | grep -F '"nix":"{'
            printf '%s\n' "$output" | grep -F 'enabled = true;'
            printf '%s\n' "$output" | grep -F '"external":"Hello, world!"'
            printf '%s\n' "$output" | grep -F '"configured":"from-nix"'
            printf '%s\n' "$output" | grep -F '"host":"example-host"'
            printf '%s\n' "$output" | grep -F '"features":["generated-data","generated-environment"]'
            printf '%s\n' "$output" | grep -F '"editor":"nvim"'
            printf '%s\n' "$output" | grep -F '"example_path":["/generated","/shared","/existing"]'
            touch $out
          '';

          bare-application = pkgs.runCommand "nu-nix-bare-application-test-result" { } ''
            output=$(${bareApplication}/bin/nu-nix-bare-application-test value)
            printf '%s\n' "$output" | grep -F '"value":"value"'
            printf '%s\n' "$output" | grep -F '"configured":"without-libraries"'
            if grep -F -- '--include-path' ${bareApplication}/bin/nu-nix-bare-application-test; then
              echo "bare Nushell applications must not receive an empty include path" >&2
              exit 1
            fi
            touch $out
          '';

          generated-modules =
            pkgs.runCommand "nu-nix-generated-modules-test"
              {
                nativeBuildInputs = [ pkgs.nushell ];
              }
              ''
                cp ${./tests/generated-modules.nu} generated-modules.nu
                substituteInPlace generated-modules.nu \
                  --replace-fail VALUE_MODULE ${generatedValueModule}/share/nushell/generated-values/mod.nu \
                  --replace-fail ENV_MODULE ${generatedEnvModule}/share/nushell/generated-env/mod.nu
                test -f ${generatedEnvModule}/share/nushell/vendor/autoload/generated-env.nu
                nu --no-config-file generated-modules.nu
                touch $out
              '';

          generated-module-validation =
            assert
              !(builtins.tryEval (
                (self.lib.mkNuModuleFromValue {
                  inherit pkgs;
                  name = "invalid-value-module";
                  values."invalid.name" = true;
                }).drvPath
              )).success;
            assert
              !(builtins.tryEval (
                (self.lib.mkNuEnvModule {
                  inherit pkgs;
                  name = "invalid-env-name-module";
                  variables."invalid.name" = true;
                }).drvPath
              )).success;
            assert
              !(builtins.tryEval (
                (self.lib.mkNuEnvModule {
                  inherit pkgs;
                  name = "invalid-env-module";
                  prependPath.PATH = "/not-a-list";
                }).drvPath
              )).success;
            assert
              !(builtins.tryEval (
                (self.lib.mkNuEnvModule {
                  inherit pkgs;
                  name = "ambiguous-env-module";
                  prependPath.PATH = [ "/first" ];
                  appendPath.PATH = [ "/last" ];
                }).drvPath
              )).success;
            pkgs.runCommand "nu-nix-generated-module-validation" { } "touch $out";

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
            test '${testSystem.config.users.users.nu-nix-test.shell.shellPath}' = '/bin/nu-bash'
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
