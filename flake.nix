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
          evaluationFails = value: !(builtins.tryEval value).success;
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
          nuCommand = self.lib.runNuCommand {
            inherit pkgs;
            name = "nu-nix-run-command-test";
            script = ./tests/run-command.nu;
            runtimeInputs = [ pkgs.hello ];
            derivationArgs.NU_NIX_RUN_COMMAND_TEST = "from-nix";
          };
          nuCommandText = self.lib.runNuCommand {
            inherit pkgs;
            name = "nu-nix-inline-command-test";
            scriptText = ''
              "inline script" | save $env.out
            '';
            nuLibraries = [ ];
          };
          fakeNix = pkgs.writeShellApplication {
            name = "nix";
            runtimeInputs = [ pkgs.coreutils ];
            text = ''
              if [[ "$*" != "print-dev-env --json fixture" ]]; then
                echo "unexpected fake nix invocation: $*" >&2
                exit 1
              fi
              cat ${./tests/fixtures/dev-env.json}
            '';
          };
          fakeJsonNix = pkgs.writeShellApplication {
            name = "nix";
            text = ''
              case "''${1-}" in
                success)
                  printf '%s\n' '{"answer":42}'
                  ;;
                fail)
                  printf '%s\n' 'not json' >&1
                  printf '%s\n' 'fixture nix failure' >&2
                  exit 23
                  ;;
                malformed)
                  printf '%s\n' '{'
                  ;;
                *)
                  printf '%s\n' 'unexpected fake nix invocation' >&2
                  exit 2
                  ;;
              esac
            '';
          };
          fakeWhyDependsNix = pkgs.writeShellApplication {
            name = "nix";
            text = ''
              if [[ "$*" != "why-depends /nix/store/example /nix/store/dependency" ]]; then
                echo "unexpected fake nix invocation: $*" >&2
                exit 1
              fi
              printf '%s\n' 'native dependency tree'
            '';
          };
          fakeLegacyNix = pkgs.symlinkJoin {
            name = "nu-nix-fake-legacy-commands";
            paths = [
              (pkgs.writeShellScriptBin "nix-build" ''
                if [[ "''${1-}" == fail ]]; then
                  exit 17
                fi
                printf '%s\n' /nix/store/example-one /nix/store/example-two
              '')
              (pkgs.writeShellScriptBin "nix-channel" ''
                if [[ "$*" != --list ]]; then
                  exit 2
                fi
                printf '%s\n' \
                  'first   https://example.test/first' \
                  $'second\thttps://example.test/second'
              '')
              (pkgs.writeShellScriptBin "nix-prefetch-url" ''
                printf 'sha256-prefetched\n\n'
              '')
              (pkgs.writeShellScriptBin "nix-hash" ''
                printf 'sha256-hashed\n\n'
              '')
            ];
          };
          generatedValueModule = self.lib.mkNuModuleFromValue {
            inherit pkgs;
            name = "generated-values";
            values = {
              answer = 42;
              control = builtins.fromJSON "\"\\u0001\"";
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
                "/duplicate"
                "/duplicate"
                "/shared"
              ];
              NU_NIX_APPEND_PATH = [
                "/existing"
                "/duplicate"
                "/duplicate"
                "/shared"
              ];
            };
            prependPath.NU_NIX_TEST_PATH = [
              "/first"
              "/shared"
              "/first"
            ];
            appendPath.NU_NIX_APPEND_PATH = [
              "/shared"
              "/last"
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

          application = pkgs.runCommand "nu-nix-application-test-result" { } ''
            ${generatedApplicationExample.application}/bin/nu-nix-generated-example tester > output.json
            ${pkgs.nushell}/bin/nu --no-config-file --commands '
              let actual = (open output.json)
              let expected = {
                greeting: "hello tester"
                nix: "{\n  enabled = true;\n}"
                external: "Hello, world!"
                configured: "from-nix"
                host: "example-host"
                features: ["generated-data" "generated-environment"]
                editor: "nvim"
                example_path: ["/generated" "/shared" "/existing"]
              }
              if $actual != $expected {
                error make {msg: $"unexpected application output: ($actual | to nuon)"}
              }
            '
            touch $out
          '';

          bare-application = pkgs.runCommand "nu-nix-bare-application-test-result" { } ''
            ${bareApplication}/bin/nu-nix-bare-application-test value > output.json
            ${pkgs.nushell}/bin/nu --no-config-file --commands '
              let actual = (open output.json)
              let expected = {value: "value", configured: "without-libraries"}
              if $actual != $expected {
                error make {msg: $"unexpected bare application output: ($actual | to nuon)"}
              }
            '
            touch $out
          '';

          run-command = nuCommand;

          run-command-text = nuCommandText;

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

          builder-validation =
            assert evaluationFails
              (self.lib.mkNuModuleFromValue {
                inherit pkgs;
                name = "invalid-value-module";
                values."invalid.name" = true;
              }).drvPath;
            assert evaluationFails
              (self.lib.mkNuModuleFromValue {
                inherit pkgs;
                name = "reserved-value-module";
                values.nu = true;
              }).drvPath;
            assert evaluationFails
              (self.lib.mkNuEnvModule {
                inherit pkgs;
                name = "invalid-env-name-module";
                variables."invalid.name" = true;
              }).drvPath;
            assert evaluationFails
              (self.lib.mkNuEnvModule {
                inherit pkgs;
                name = "invalid-env-path-entry-module";
                prependPath.PATH = [ 42 ];
              }).drvPath;
            assert evaluationFails
              (self.lib.mkNuEnvModule {
                inherit pkgs;
                name = "invalid-env-module";
                prependPath.PATH = "/not-a-list";
              }).drvPath;
            assert evaluationFails
              (self.lib.mkNuEnvModule {
                inherit pkgs;
                name = "ambiguous-env-module";
                prependPath.PATH = [ "/first" ];
                appendPath.PATH = [ "/last" ];
              }).drvPath;
            assert evaluationFails
              (self.lib.mkNuModule {
                inherit pkgs;
                name = "../invalid-module";
                src = ./tests/bare-application;
              }).drvPath;
            assert evaluationFails
              (self.lib.mkNuApplication {
                inherit pkgs;
                name = "../invalid-application";
                src = ./tests/bare-application;
              }).drvPath;
            assert evaluationFails
              (self.lib.mkNuApplication {
                inherit pkgs;
                name = "invalid-entrypoint-application";
                src = ./tests/bare-application;
                entrypoint = "../main.nu";
              }).drvPath;
            assert evaluationFails
              (self.lib.mkNuApplication {
                inherit pkgs;
                name = "invalid-environment-name-application";
                src = ./tests/bare-application;
                environment."invalid.name" = "value";
              }).drvPath;
            assert evaluationFails
              (self.lib.mkNuApplication {
                inherit pkgs;
                name = "invalid-environment-value-application";
                src = ./tests/bare-application;
                environment.INVALID_VALUE = [
                  "not"
                  "a string"
                ];
              }).drvPath;
            assert evaluationFails
              (self.lib.runNuCommand {
                inherit pkgs;
                name = "../invalid-command";
                script = ./tests/run-command.nu;
              }).drvPath;
            assert evaluationFails
              (self.lib.runNuCommand {
                inherit pkgs;
                name = "missing-command-script";
              }).drvPath;
            assert evaluationFails
              (self.lib.runNuCommand {
                inherit pkgs;
                name = "ambiguous-command-script";
                scriptFile = ./tests/run-command.nu;
                scriptText = "print ambiguous";
              }).drvPath;
            assert evaluationFails
              (self.lib.runNuCommand {
                inherit pkgs;
                name = "invalid-command-script";
                script = [ ./tests/run-command.nu ];
              }).drvPath;
            pkgs.runCommand "nu-nix-builder-validation" { } "touch $out";

          package-autoload-shape = pkgs.runCommand "nu-nix-package-autoload-shape-test" { } ''
            test -d ${pkg}/share/nushell/nu-nix
            test ! -e ${pkg}/share/nushell/vendor/autoload/nu-nix.nu
            touch $out
          '';

          nixos-autoload = pkgs.runCommand "nu-nix-nixos-autoload-test" { } ''
            test -f ${testSystem.config.system.path}/share/nushell/vendor/autoload/nu-nix.nu
            printf '%s\n' 'use ${pkg}/share/nushell/nu-nix *' > expected-autoload.nu
            cmp expected-autoload.nu \
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
            mkdir -p support
            cp ${./tests/test_to_nix.nu} test_to_nix.nu
            cp ${./tests/support/assert.nu} support/assert.nu
            substituteInPlace test_to_nix.nu \
              --replace-fail '../package/scripts/nu-nix/mod.nu' \
                        '${pkg}/share/nushell/nu-nix/mod.nu'
            nu --no-config-file test_to_nix.nu
            touch $out
          '';

          # Hermetic Nix evaluation and codec round-trip tests.
          from-nix-tests =
            pkgs.runCommand "nu-nix-from-nix-tests"
              {
                nativeBuildInputs = [
                  pkgs.nix
                  pkgs.nushell
                ];
                NIX_CONFIG = "experimental-features = nix-command";
              }
              ''
                export HOME="$PWD/home"
                mkdir -p "$HOME" support
                cp ${./tests/test_from_nix.nu} test_from_nix.nu
                cp ${./tests/support/assert.nu} support/assert.nu
                substituteInPlace test_from_nix.nu \
                  --replace-fail '../package/scripts/nu-nix/mod.nu' \
                            '${pkg}/share/nushell/nu-nix/mod.nu'
                nu --no-config-file test_from_nix.nu
                touch $out
              '';

          command-normalizer-tests =
            pkgs.runCommand "nu-nix-command-normalizer-tests"
              {
                nativeBuildInputs = [ pkgs.nushell ];
              }
              ''
                mkdir -p package/scripts/nu-nix tests/support
                cp ${./package/scripts/nu-nix/normalize.nu} package/scripts/nu-nix/normalize.nu
                cp ${./package/scripts/nu-nix/completions.nu} package/scripts/nu-nix/completions.nu
                cp ${./tests/test_commands.nu} tests/test_commands.nu
                cp ${./tests/support/assert.nu} tests/support/assert.nu
                nu --no-config-file tests/test_commands.nu
                touch $out
              '';

          internal-tests =
            pkgs.runCommand "nu-nix-internal-tests"
              {
                nativeBuildInputs = [
                  fakeJsonNix
                  pkgs.nushell
                ];
              }
              ''
                mkdir -p tests/support
                cp ${./tests/test_internal.nu} tests/test_internal.nu
                cp ${./tests/support/assert.nu} tests/support/assert.nu
                substituteInPlace tests/test_internal.nu \
                  --replace-fail 'MODULE' '${pkg}/share/nushell/nu-nix/internal.nu'
                nu --no-config-file tests/test_internal.nu
                touch $out
              '';

          activation-tests =
            pkgs.runCommand "nu-nix-activation-tests"
              {
                nativeBuildInputs = [
                  fakeNix
                  pkgs.nushell
                ];
              }
              ''
                export PATH=${fakeNix}/bin:$PATH
                mkdir -p tests/support
                cp ${./tests/test_activation.nu} tests/test_activation.nu
                cp ${./tests/support/assert.nu} tests/support/assert.nu
                substituteInPlace tests/test_activation.nu \
                  --replace-fail 'MODULE' '${pkg}/share/nushell/nu-nix/mod.nu'
                nu --no-config-file tests/test_activation.nu
                touch $out
              '';

          completion-tests =
            pkgs.runCommand "nu-nix-completion-tests"
              {
                nativeBuildInputs = [
                  pkgs.nix
                  pkgs.nushell
                ];
                NIX_CONFIG = "experimental-features = nix-command flakes";
              }
              ''
                export HOME="$PWD/home"
                mkdir -p "$HOME" tests/support
                cp ${./tests/test_completions.nu} tests/test_completions.nu
                cp ${./tests/support/assert.nu} tests/support/assert.nu
                substituteInPlace tests/test_completions.nu \
                  --replace-fail 'MODULE' '${pkg}/share/nushell/nu-nix/mod.nu' \
                  --replace-fail 'FIXTURE' '${./tests/fixtures/completion-flake}'
                nu --no-config-file tests/test_completions.nu
                touch $out
              '';

          why-depends-passthrough =
            pkgs.runCommand "nu-nix-why-depends-passthrough-test"
              {
                nativeBuildInputs = [
                  fakeWhyDependsNix
                  pkgs.nushell
                ];
              }
              ''
                mkdir -p tests/support
                cp ${./tests/test_passthrough.nu} tests/test_passthrough.nu
                cp ${./tests/support/assert.nu} tests/support/assert.nu
                substituteInPlace tests/test_passthrough.nu \
                  --replace-fail 'MODULE' '${pkg}/share/nushell/nu-nix/mod.nu'
                nu --no-config-file tests/test_passthrough.nu
                touch $out
              '';

          legacy-wrappers =
            pkgs.runCommand "nu-nix-legacy-wrappers-test"
              {
                nativeBuildInputs = [
                  fakeLegacyNix
                  pkgs.nushell
                ];
              }
              ''
                mkdir -p tests/support
                cp ${./tests/test_legacy.nu} tests/test_legacy.nu
                cp ${./tests/support/assert.nu} tests/support/assert.nu
                substituteInPlace tests/test_legacy.nu \
                  --replace-fail 'MODULE' '${pkg}/share/nushell/nu-nix/mod.nu'
                nu --no-config-file tests/test_legacy.nu
                touch $out
              '';

          nu-bash-login =
            pkgs.runCommand "nu-bash-login-test"
              {
                nativeBuildInputs = [
                  pkgs.coreutils
                  pkgs.util-linux
                ];
              }
              ''
                export HOME="$PWD/home"
                export XDG_CONFIG_HOME="$PWD/config"
                export NU_BASH_TEST_RESULT="$PWD/login-result"
                mkdir -p "$HOME" "$XDG_CONFIG_HOME/nushell"

                printf '%s\n' \
                  '$nu.is-login | save --force $env.NU_BASH_TEST_RESULT' \
                  'exit' \
                  > "$XDG_CONFIG_HOME/nushell/login.nu"

                timeout 10 script -qefc \
                  '${pkg}/bin/nu-bash > nu-stdout' \
                  /dev/null \
                  < /dev/null

                test "$(cat "$NU_BASH_TEST_RESULT")" = true
                touch $out
              '';
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
