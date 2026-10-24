{
  self,
  nixpkgs,
  flake-parts,
  pkgs,
}:
let
  project = {
    examples = ../../examples;
    nushell = ../../nushell;
    tests = ../.;
  };
  completionFixture = ../fixtures/completion-flake;
  system = pkgs.stdenv.hostPlatform.system;
  pkg = self.packages.${system}.default;
  nativePlugin = self.packages.${system}.native-plugin;
  nuNixBash = self.packages.${system}.nu-nix-bash;
  evaluationFails = value: !(builtins.tryEval value).success;
  checkAssertions =
    assertions:
    let
      failures = builtins.attrNames (pkgs.lib.filterAttrs (_: passed: !passed) assertions);
    in
    ''
      failures=${pkgs.lib.escapeShellArg (builtins.concatStringsSep ", " failures)}
      if [[ -n "$failures" ]]; then
        echo "failed assertions: $failures" >&2
        exit 1
      fi
    '';
  integratedProjectExample = import (project.examples + "/integrated-project/default.nix") {
    inherit pkgs;
    nu-nix = self;
  };
  inherit (integratedProjectExample) nuSession;
  buildPipelineExample = import (project.examples + "/build-pipeline/default.nix") {
    inherit pkgs;
    nu-nix = self;
  };
  bareApplication = self.lib.mkNuApplication {
    inherit pkgs;
    name = "nu-nix-bare-application-test";
    src = project.tests + "/bare-application";
    nuLibraries = [ ];
    environment.NU_NIX_BARE_TEST = "without-libraries";
  };
  nuCommand = self.lib.runNuCommand {
    inherit pkgs;
    name = "nu-nix-run-command-test";
    scriptFile = project.tests + "/nushell/run-command.nu";
    runtimeInputs = [ pkgs.hello ];
    derivationArgs.NU_NIX_RUN_COMMAND_TEST = "native";
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
      cat ${project.tests}/fixtures/dev-env.json
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
  fakeProfileNix = pkgs.writeShellApplication {
    name = "nix";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      if [[ "''${1-}" != profile ]]; then
        echo "unexpected fake nix invocation: $*" >&2
        exit 2
      fi

      case "''${2-}" in
        add)
          printf '%s' 1 > "$NU_NIX_FAKE_PROFILE_STATE"
          ;;
        upgrade)
          printf '%s' 2 > "$NU_NIX_FAKE_PROFILE_STATE"
          ;;
        rollback)
          printf '%s' 1 > "$NU_NIX_FAKE_PROFILE_STATE"
          ;;
        remove)
          rm -f "$NU_NIX_FAKE_PROFILE_STATE"
          ;;
        history)
          printf '%s\n' 'Version 1' 'Version 2 <- 1'
          ;;
        list)
          if [[ "''${3-}" != --json ]]; then
            echo "profile list must request JSON: $*" >&2
            exit 2
          fi
          if [[ -f "$NU_NIX_FAKE_PROFILE_STATE" ]]; then
            version=$(<"$NU_NIX_FAKE_PROFILE_STATE")
            printf '{"elements":{"environment":{"active":true,"storePaths":["/nix/store/environment-%s"],"version":"%s"}}}\n' \
              "$version" "$version"
          else
            printf '%s\n' '{"elements":{}}'
          fi
          ;;
        *)
          echo "unexpected fake profile action: $*" >&2
          exit 2
          ;;
      esac
    '';
  };
  fakeWhyDependsNix = pkgs.writeShellApplication {
    name = "nix";
    text = ''
      case "$*" in
        "why-depends /nix/store/example /nix/store/dependency")
          printf '%s\n' 'native dependency tree'
          ;;
        "unsupported-command --flag value")
          printf '%s\n' 'raw fallback: unsupported-command --flag value'
          ;;
        "profile list")
          printf '%s\n' 'raw dynamic dispatch: profile list'
          ;;
        "")
          printf '%s\n' 'raw fallback: root'
          ;;
        "unsupported-failure")
          printf '%s\n' 'raw fallback failure' >&2
          exit 23
          ;;
        *)
          echo "unexpected fake nix invocation: $*" >&2
          exit 1
          ;;
      esac
    '';
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
  generatedTask = self.lib.mkNuTask {
    inherit pkgs;
    description = "Generated task";
    deps = [ "prepare" ];
    runtimeInputs = [ pkgs.hello ];
    environment.NU_NIX_TASK = "configured";
    script = project.tests + "/nushell/run-command.nu";
  };
  generatedDerivationTask = self.lib.mkDerivationTask {
    inherit pkgs;
    description = "Generated derivation task";
    deps = [ "prepare" ];
    targets = {
      dev = pkgs.openssl.dev;
      inherit (pkgs) hello jq;
    };
  };
  generatedExport = self.lib.mkNuExport {
    inherit pkgs;
    description = "Add values";
    arguments = [
      "left"
      "right"
    ];
    result = "collect";
    function = left: right: left + right;
  };
  generatedPureExport = self.lib.mkNuExport {
    inherit (pkgs) lib;
    arguments = [ "value" ];
    function = value: value;
  };
  generatedPureDerivationTask = self.lib.mkDerivationTask {
    inherit (pkgs) lib;
    targets.default = pkgs.hello;
  };
  flakePartsResult = flake-parts.lib.mkFlake { inputs = { inherit self; }; } {
    systems = [ system ];
    imports = [ self.flakeModules.default ];
    perSystem =
      { pkgs, ... }:
      {
        nushell.modules.example = {
          package = pkgs.hello;
          entrypoint = "share/example/mod.nu";
          description = "Example module";
        };
        nushell.exports.add = generatedExport;
        tasks.example = generatedTask;
      };
  };
  invalidFlakePartsTask = flake-parts.lib.mkFlake { inputs = { inherit self; }; } {
    systems = [ system ];
    imports = [ self.flakeModules.default ];
    perSystem.tasks.invalid = {
      type = "not-a-task";
      version = 2;
      description = "Invalid task";
      deps = [ ];
      action.type = "nushell";
    };
  };
  invalidFlakePartsPublication = flake-parts.lib.mkFlake { inputs = { inherit self; }; } {
    systems = [ system ];
    imports = [ self.flakeModules.default ];
    perSystem =
      { pkgs, ... }:
      {
        nushell.modules.invalid = {
          package = pkgs.hello;
          entrypoint = "../bin/hello";
        };
      };
  };
  invalidFlakePartsMissingEntrypoint = flake-parts.lib.mkFlake { inputs = { inherit self; }; } {
    systems = [ system ];
    imports = [ self.flakeModules.default ];
    perSystem =
      { pkgs, ... }:
      {
        nushell.modules.invalid.package = pkgs.hello;
      };
  };
  invalidFlakePartsExport = flake-parts.lib.mkFlake { inputs = { inherit self; }; } {
    systems = [ system ];
    imports = [ self.flakeModules.default ];
    perSystem.nushell.exports.invalid = {
      arguments = [ ];
      function = value: value;
    };
  };
  invalidFlakePartsExportFunction = flake-parts.lib.mkFlake { inputs = { inherit self; }; } {
    systems = [ system ];
    imports = [ self.flakeModules.default ];
    perSystem.nushell.exports.invalid = {
      arguments = [ "value" ];
      function = 42;
    };
  };
  exampleTasks = integratedProjectExample.tasks;
  exampleInputs = {
    nu-nix = self;
    project.packages.${system}.session = nuSession;
  };
  testSystem = nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs.inputs = exampleInputs;
    modules = [
      (project.examples + "/nixos.nix")
      ({ config, ... }: {
        system.stateVersion = "26.05";
        users.users.alice = {
          isNormalUser = true;
          shell = config.programs.nu-nix.loginShellPackage;
        };
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
    specialArgs = {
      inherit pkgs;
      inputs = exampleInputs;
    };
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
      (project.examples + "/home-manager.nix")
    ];
  };
in
{
  package = pkg;

  native-plugin = nativePlugin;

  native-plugin-tests =
    pkgs.runCommand "nu-nix-native-plugin-tests"
      {
        nativeBuildInputs = [ pkgs.nushell ];
      }
      ''
        export HOME="$PWD/home"
        mkdir -p "$HOME" tests/support
        cp ${project.tests}/nushell/test_native_plugin.nu tests/test_native_plugin.nu
        cp ${project.tests}/nushell/support/assert.nu tests/support/assert.nu
        nu --no-config-file \
          --plugins ${nativePlugin}/bin/nu_plugin_nix \
          tests/test_native_plugin.nu
        touch $out
      '';

  native-task-tests =
    pkgs.runCommand "nu-nix-native-task-tests"
      {
        nativeBuildInputs = [
          pkgs.nix
          pkgs.nushell
        ];
        NIX_CONFIG = ''
          experimental-features = nix-command flakes
          substituters =
        '';
      }
      ''
        export HOME="$PWD/home"
        mkdir -p "$HOME" tests/support
        cp -R ${project.tests}/fixtures/task-flake fixture
        cp -R ${project.tests}/fixtures/malformed-task-flake malformed-fixture
        chmod -R u+w fixture
        chmod -R u+w malformed-fixture
        cp ${project.tests}/nushell/test_tasks.nu tests/test_tasks.nu
        cp ${project.tests}/nushell/support/assert.nu tests/support/assert.nu
        substituteInPlace tests/test_tasks.nu \
          --replace-fail 'MODULE' '${pkg}/share/nushell/nu-nix/mod.nu' \
          --replace-fail 'SYSTEM' '${system}' \
          --replace-fail 'MALFORMED_FIXTURE' "$PWD/malformed-fixture" \
          --replace-fail 'FIXTURE' "$PWD/fixture"
        substituteInPlace fixture/flake.nix \
          --replace-fail 'SYSTEM' '${system}'
        substituteInPlace malformed-fixture/flake.nix \
          --replace-fail 'SYSTEM' '${system}'
        export NU_NIX_SKIP_NESTED_BUILDS=1
        test -f ${
          builtins.path {
            path = project.tests + "/fixtures/task-flake";
            name = "source";
          }
        }/helper.nu
        nu --no-config-file \
          --plugins ${nativePlugin}/bin/nu_plugin_nix \
          tests/test_tasks.nu
        touch $out
      '';

  task-example-tests =
    pkgs.runCommand "nu-nix-task-example-tests" { nativeBuildInputs = [ pkgs.nushell ]; }
      ''
        export HOME="$PWD/home"
        mkdir -p "$HOME"
        ${checkAssertions {
          task-names =
            builtins.attrNames exampleTasks == [
              "check"
              "prepare"
              "runtime"
              "show"
            ];
          prepare-dependencies = exampleTasks.prepare.deps == [ "runtime" ];
          check-dependencies = exampleTasks.check.deps == [ "prepare" ];
          show-dependencies = exampleTasks.show.deps == [ "check" ];
        }}
        nu --no-config-file --commands \
          'if not (nu-check ${project.examples}/integrated-project/tasks/prepare.nu) { exit 1 }'
        nu --no-config-file --commands \
          'if not (nu-check ${project.examples}/integrated-project/tasks/check.nu) { exit 1 }'
        nu --no-config-file --commands \
          'if not (nu-check ${project.examples}/integrated-project/tasks/show.nu) { exit 1 }'
        nu --no-config-file \
          --plugins ${nativePlugin}/bin/nu_plugin_nix \
          --commands '
            use ${pkg}/share/nushell/nu-nix/mod.nu *
            if not (nu-check --debug ${project.examples}/native-values.nu) { exit 1 }
            if not (nu-check --debug ${project.examples}/native-functions.nu) { exit 1 }
          '
        touch $out
      '';

  build-pipeline-example =
    pkgs.runCommand "nu-nix-build-pipeline-example-test"
      {
        nativeBuildInputs = [ pkgs.nushell ];
      }
      ''
        ${checkAssertions {
          task-names =
            builtins.attrNames buildPipelineExample.tasks == [
              "build"
              "check"
              "publish"
            ];
          publish-dependencies = buildPipelineExample.tasks.publish.deps == [ "build" ];
          check-dependencies = buildPipelineExample.tasks.check.deps == [ "publish" ];
        }}
        nu --no-config-file --commands '
          let report = (open ${buildPipelineExample.report}/report.json)
          if $report != {
            project: build-pipeline
            version: "1"
            item_count: 3
            enabled_count: 2
            enabled: [
              {name: alpha, owner: platform}
              {name: gamma, owner: platform}
            ]
          } {
            error make {msg: $"unexpected build pipeline report: ($report | to nuon)"}
          }
        '
        nu --no-config-file --commands \
          'if not (nu-check ${project.examples}/build-pipeline/module/mod.nu) { exit 1 }'
        nu --no-config-file --commands \
          'if not (nu-check ${project.examples}/build-pipeline/tasks/publish.nu) { exit 1 }'
        nu --no-config-file --commands \
          'if not (nu-check ${project.examples}/build-pipeline/tasks/check.nu) { exit 1 }'
        touch $out
      '';

  application = pkgs.runCommand "nu-nix-application-test-result" { } ''
    export HOME="$PWD/home"
    mkdir -p "$HOME"
    ${integratedProjectExample.application}/bin/nu-nix-generated-example tester > output.json
    ${pkgs.nushell}/bin/nu --no-config-file --commands '
      let actual = (open output.json)
      let expected = {
        greeting: "hello tester"
        nix: "{\n  enabled = true;\n}"
        evaluated: 42
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

  nushell-session = pkgs.runCommand "nu-nix-session-test-result" { } ''
    export HOME="$PWD/home"
    mkdir -p "$HOME"
    test ! -e ${nuSession}/share/nushell/session/plugin.msgpackz
    ${nuSession}/bin/nu-nix-integrated-session --no-config-file --commands '
      use context *
      let evaluated = (nix eval "40 + 2" | nix collect)
      let report = (^greeter tester | from json)
      let manifest = (open ${nuSession}/share/nushell/session/manifest.json)
      if $host != "example-host" {
        error make {msg: "composed module is unavailable"}
      }
      if $evaluated != 42 {
        error make {msg: "composed plugin is unavailable"}
      }
      if $report.greeting != "hello tester" {
        error make {msg: "composed application is unavailable"}
      }
      if (which jq | is-empty) {
        error make {msg: "ordinary Nix package is unavailable"}
      }
      if (
        $manifest.modules.0.name != "context"
        or $manifest.plugins.0.name != "nix"
        or $manifest.applications.0.name != "greeter"
      ) {
        error make {msg: "environment manifest does not describe the active components"}
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
        cp ${project.tests}/nushell/generated-modules.nu generated-modules.nu
        substituteInPlace generated-modules.nu \
          --replace-fail VALUE_MODULE ${generatedValueModule}/share/nushell/generated-values/mod.nu \
          --replace-fail ENV_MODULE ${generatedEnvModule}/share/nushell/generated-env/mod.nu
        test -f ${generatedEnvModule}/share/nushell/vendor/autoload/generated-env.nu
        nu --no-config-file generated-modules.nu
        touch $out
      '';

  builder-validation =
    assert nuSession.nushellSession.version == 1;
    assert nuSession.nushellSession.name == "nu-nix-integrated-session";
    assert (builtins.head nuSession.nushellSession.modules).name == "context";
    assert (builtins.head nuSession.nushellSession.plugins).name == "nix";
    assert (builtins.head nuSession.nushellSession.applications).name == "greeter";
    assert generatedTask.type == "nu-nix-task";
    assert generatedTask.version == 2;
    assert generatedTask.description == "Generated task";
    assert generatedTask.deps == [ "prepare" ];
    assert generatedTask.action.type == "nushell";
    assert generatedTask.action.environment.NU_NIX_TASK == "configured";
    assert generatedTask.action.script.type == "file";
    assert pkgs.lib.hasInfix "/bin" generatedTask.action.path;
    assert generatedDerivationTask.type == "nu-nix-task";
    assert generatedDerivationTask.version == 2;
    assert generatedDerivationTask.action.type == "realise";
    assert generatedExport.type == "nu-nix-export";
    assert generatedExport.version == 1;
    assert generatedExport.result == "collect";
    assert generatedPureExport.type == "nu-nix-export";
    assert generatedPureDerivationTask.action.type == "realise";
    assert flakePartsResult.nushell.${system}.type == "nu-nix-interface";
    assert flakePartsResult.nushell.${system}.version == 1;
    assert flakePartsResult.nushell.${system}.modules.example.entrypoint == "share/example/mod.nu";
    assert flakePartsResult.nushell.${system}.modules.example.type == "nu-nix-publication";
    assert flakePartsResult.nushell.${system}.modules.example.role == "module";
    assert builtins.isString flakePartsResult.nushell.${system}.modules.example.package;
    assert builtins.hasContext flakePartsResult.nushell.${system}.modules.example.package;
    assert flakePartsResult.nushell.${system}.exports.add.description == "Add values";
    assert flakePartsResult.tasks.${system}.example.type == "nu-nix-task";
    assert flakePartsResult.tasks.${system}.example.action.type == "nushell";
    assert evaluationFails (builtins.deepSeq invalidFlakePartsTask.tasks.${system}.invalid true);
    assert evaluationFails (
      builtins.deepSeq invalidFlakePartsPublication.nushell.${system}.modules.invalid true
    );
    assert evaluationFails (
      builtins.deepSeq invalidFlakePartsMissingEntrypoint.nushell.${system}.modules.invalid true
    );
    assert evaluationFails (
      builtins.deepSeq invalidFlakePartsExport.nushell.${system}.exports.invalid true
    );
    assert evaluationFails (
      builtins.deepSeq invalidFlakePartsExportFunction.nushell.${system}.exports.invalid true
    );
    assert
      builtins.attrNames generatedDerivationTask.action.targets == [
        "dev"
        "hello"
        "jq"
      ];
    assert generatedDerivationTask.action.targets.dev == "${pkgs.openssl.dev}";
    assert pkgs.lib.hasInfix "-hello-" generatedDerivationTask.action.targets.hello;
    assert evaluationFails (
      builtins.deepSeq (self.lib.mkDerivationTask {
        inherit pkgs;
        targets = { };
      }) true
    );
    assert evaluationFails (
      builtins.deepSeq (self.lib.mkDerivationTask {
        inherit pkgs;
        targets.invalid = "not-a-derivation";
      }) true
    );
    assert evaluationFails (
      builtins.deepSeq (self.lib.mkDerivationTask {
        inherit pkgs;
        targets."invalid.name" = pkgs.hello;
      }) true
    );
    assert evaluationFails (
      builtins.deepSeq (self.lib.mkDerivationTask {
        inherit pkgs;
        description = 42;
        targets.valid = pkgs.hello;
      }) true
    );
    assert evaluationFails (
      builtins.deepSeq (self.lib.mkDerivationTask {
        inherit pkgs;
        deps = [ 42 ];
        targets.valid = pkgs.hello;
      }) true
    );
    assert evaluationFails (
      builtins.deepSeq (self.lib.mkNuTask {
        inherit pkgs;
        script = project.tests + "/nushell/run-command.nu";
        deps = [ 42 ];
      }) true
    );
    assert evaluationFails (
      builtins.deepSeq (self.lib.mkNuTask {
        inherit pkgs;
        script = project.tests + "/nushell/run-command.nu";
        environment.PATH = "/unexpected";
      }) true
    );
    assert evaluationFails (
      builtins.deepSeq (self.lib.mkNuTask {
        inherit pkgs;
        script = project.tests + "/nushell/run-command.nu";
        environment."invalid.name" = "value";
      }) true
    );
    assert evaluationFails (
      builtins.deepSeq (self.lib.mkNuTask {
        inherit pkgs;
        script = project.tests + "/nushell/run-command.nu";
        runtimeInputs = [ "not-a-derivation" ];
      }) true
    );
    assert evaluationFails (
      builtins.deepSeq (self.lib.mkNuTask {
        inherit pkgs;
        script = "print inline";
        sourceRoot = project.tests;
      }) true
    );
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
        src = project.tests + "/bare-application";
      }).drvPath;
    assert evaluationFails
      (self.lib.mkNuApplication {
        inherit pkgs;
        name = "../invalid-application";
        src = project.tests + "/bare-application";
      }).drvPath;
    assert evaluationFails
      (self.lib.mkNuApplication {
        inherit pkgs;
        name = "invalid-entrypoint-application";
        src = project.tests + "/bare-application";
        entrypoint = "../main.nu";
      }).drvPath;
    assert evaluationFails
      (self.lib.mkNuApplication {
        inherit pkgs;
        name = "invalid-environment-name-application";
        src = project.tests + "/bare-application";
        environment."invalid.name" = "value";
      }).drvPath;
    assert evaluationFails
      (self.lib.mkNuApplication {
        inherit pkgs;
        name = "invalid-environment-value-application";
        src = project.tests + "/bare-application";
        environment.INVALID_VALUE = [
          "not"
          "a string"
        ];
      }).drvPath;
    assert evaluationFails
      (self.lib.mkNuApplication {
        inherit pkgs;
        name = "invalid-plugin-application";
        src = project.tests + "/bare-application";
        plugins = "not-a-list";
      }).drvPath;
    assert evaluationFails
      (self.lib.mkNuSession {
        inherit pkgs;
        name = "invalid-session-publication";
        modules.invalid = {
          role = "plugin";
          package = pkgs.hello;
          entrypoint = "share/nushell/invalid/mod.nu";
        };
      }).drvPath;
    assert evaluationFails
      (self.lib.mkNuSession {
        inherit pkgs;
        name = "missing-session-entrypoint";
        modules.missing.package = pkgs.hello;
      }).drvPath;
    assert evaluationFails
      (self.lib.mkNuSession {
        inherit pkgs;
        name = "invalid-session-package";
        packages = [ "untracked-package" ];
      }).drvPath;
    assert evaluationFails
      (self.lib.runNuCommand {
        inherit pkgs;
        name = "../invalid-command";
        scriptFile = project.tests + "/nushell/run-command.nu";
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
        scriptFile = project.tests + "/nushell/run-command.nu";
        scriptText = "print ambiguous";
      }).drvPath;
    assert evaluationFails
      (self.lib.runNuCommand {
        inherit pkgs;
        name = "invalid-command-script";
        scriptFile = [ (project.tests + "/nushell/run-command.nu") ];
      }).drvPath;
    assert evaluationFails
      (self.lib.runNuCommand {
        inherit pkgs;
        name = "invalid-plugin-command";
        scriptFile = project.tests + "/nushell/run-command.nu";
        plugins = [ 42 ];
      }).drvPath;
    pkgs.runCommand "nu-nix-builder-validation" { } "touch $out";

  package-autoload-shape = pkgs.runCommand "nu-nix-package-autoload-shape-test" { } ''
    test -d ${pkg}/share/nushell/nu-nix
    test -f ${pkg}/share/nushell/nu-nix/plugin.msgpackz
    test ! -e ${pkg}/bin/nu-nix-bash
    test -x ${nuNixBash}/bin/nu-nix-bash
    test ! -e ${pkg}/share/nushell/vendor/autoload/nu-nix.nu
    touch $out
  '';

  nixos-autoload = pkgs.runCommand "nu-nix-nixos-autoload-test" { } ''
    test ${builtins.toString (builtins.elem nuSession testSystem.config.environment.systemPackages)} = 1
    test -f ${testSystem.config.system.path}/share/nushell/vendor/autoload/nu-nix.nu
    cat > expected-autoload.nu <<'EOF'
    plugin use --plugin-config ${pkg}/share/nushell/nu-nix/plugin.msgpackz nix
    use ${pkg}/share/nushell/nu-nix *
    EOF
    cmp expected-autoload.nu \
      ${testSystem.config.system.path}/share/nushell/vendor/autoload/nu-nix.nu
    export HOME="$PWD/home"
    mkdir -p "$HOME"
    ${pkgs.nushell}/bin/nu --no-config-file --commands '
      source ${testSystem.config.system.path}/share/nushell/vendor/autoload/nu-nix.nu
      let actual = (nix eval "1 + 1" | nix collect)
      if $actual != 2 { error make { msg: "autoloaded native evaluator failed" } }
      let inventory = (nix commands)
      if "nix eval" not-in $inventory.command {
        error make { msg: "native evaluator missing from command inventory" }
      }
      let diagnostic = ($inventory | where command == "nix debug runtime status")
      if ($diagnostic | length) != 1 or $diagnostic.0.group != "diagnostic" {
        error make { msg: "runtime status is not classified as a diagnostic" }
      }
      if "nix value release" in $inventory.command {
        error make { msg: "obsolete explicit release command is still registered" }
      }
    '
        test '${testSystem.config.users.users.alice.shell.shellPath}' = '/bin/nu-nix-bash'
    touch $out
  '';

  nixos-no-autoload = pkgs.runCommand "nu-nix-nixos-no-autoload-test" { } ''
    test -d ${testSystemNoAutoload.config.system.path}/share/nushell/nu-nix
    test ! -e ${testSystemNoAutoload.config.system.path}/share/nushell/vendor/autoload/nu-nix.nu
    touch $out
  '';

  home-manager-autoload = pkgs.runCommand "nu-nix-home-manager-autoload-test" { } ''
    test ${builtins.toString (builtins.elem nuSession testHome.config.home.packages)} = 1
    test ${builtins.toString (builtins.elem pkg testHome.config.home.packages)} = 1
    test ${builtins.toString (builtins.elem pkgs.nushell testHome.config.home.packages)} = 1
    test ${builtins.toString (!(builtins.elem nuNixBash testHome.config.home.packages))} = 1
    test ${
      builtins.toString (
        testHome.config.xdg.configFile."nushell/autoload/nu-nix.nu".text == ''
          plugin use --plugin-config ${pkg}/share/nushell/nu-nix/plugin.msgpackz nix
          use ${pkg}/share/nushell/nu-nix *
        ''
      )
    } = 1
    touch $out
  '';

  # Pure Nushell tests for `to nix` — no Nix evaluation, runs in sandbox.
  to-nix-tests = pkgs.runCommand "nu-nix-to-nix-tests" { buildInputs = [ pkgs.nushell ]; } ''
    mkdir -p support
    cp ${project.tests}/nushell/test_to_nix.nu test_to_nix.nu
    cp ${project.tests}/nushell/support/assert.nu support/assert.nu
    substituteInPlace test_to_nix.nu \
      --replace-fail '../../nushell/nu-nix/mod.nu' \
                '${pkg}/share/nushell/nu-nix/mod.nu'
    nu --no-config-file test_to_nix.nu
    touch $out
  '';

  command-normalizer-tests =
    pkgs.runCommand "nu-nix-command-normalizer-tests"
      {
        nativeBuildInputs = [ pkgs.nushell ];
      }
      ''
        mkdir -p nushell/nu-nix tests/nushell/support
        cp ${project.nushell}/nu-nix/normalize.nu nushell/nu-nix/normalize.nu
        cp ${project.nushell}/nu-nix/completions.nu nushell/nu-nix/completions.nu
        cp ${project.nushell}/nu-nix/system.nu nushell/nu-nix/system.nu
        cp ${project.tests}/nushell/test_cli.nu tests/nushell/test_cli.nu
        cp ${project.tests}/nushell/support/assert.nu tests/nushell/support/assert.nu
        nu --no-config-file tests/nushell/test_cli.nu
        touch $out
      '';

  cli-process-tests =
    pkgs.runCommand "nu-nix-cli-process-tests"
      {
        nativeBuildInputs = [
          fakeJsonNix
          pkgs.nushell
        ];
      }
      ''
        mkdir -p tests/support
        cp ${project.tests}/nushell/test_cli_process.nu tests/test_cli_process.nu
        cp ${project.tests}/nushell/support/assert.nu tests/support/assert.nu
        substituteInPlace tests/test_cli_process.nu \
          --replace-fail 'MODULE' '${pkg}/share/nushell/nu-nix/cli-process.nu'
        nu --no-config-file tests/test_cli_process.nu
        touch $out
      '';

  profile-lifecycle-tests =
    pkgs.runCommand "nu-nix-profile-lifecycle-tests"
      {
        nativeBuildInputs = [
          fakeProfileNix
          pkgs.nushell
        ];
      }
      ''
        export NU_NIX_FAKE_PROFILE_STATE="$PWD/profile-state"
        mkdir -p tests/support
        cp ${project.tests}/nushell/test_profile.nu tests/test_profile.nu
        cp ${project.tests}/nushell/support/assert.nu tests/support/assert.nu
        substituteInPlace tests/test_profile.nu \
          --replace-fail 'MODULE' '${pkg}/share/nushell/nu-nix/mod.nu' \
          --replace-fail 'PROFILE' "$PWD/profile"
        nu --no-config-file tests/test_profile.nu
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
        cp ${project.tests}/nushell/test_activation.nu tests/test_activation.nu
        cp ${project.tests}/nushell/support/assert.nu tests/support/assert.nu
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
        cp ${project.tests}/nushell/test_completions.nu tests/test_completions.nu
        cp ${project.tests}/nushell/support/assert.nu tests/support/assert.nu
        substituteInPlace tests/test_completions.nu \
          --replace-fail 'MODULE' '${pkg}/share/nushell/nu-nix/mod.nu' \
          --replace-fail 'FIXTURE' '${completionFixture}'
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
        cp ${project.tests}/nushell/test_passthrough.nu tests/test_passthrough.nu
        cp ${project.tests}/nushell/support/assert.nu tests/support/assert.nu
        substituteInPlace tests/test_passthrough.nu \
          --replace-fail 'MODULE' '${pkg}/share/nushell/nu-nix/mod.nu'
        nu --no-config-file tests/test_passthrough.nu
        touch $out
      '';

  nu-nix-bash-login =
    pkgs.runCommand "nu-nix-bash-login-test"
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
          '${nuNixBash}/bin/nu-nix-bash > nu-stdout' \
          /dev/null \
          < /dev/null

        test "$(cat "$NU_BASH_TEST_RESULT")" = true
        touch $out
      '';
}
