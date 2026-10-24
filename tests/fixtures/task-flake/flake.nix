{
  outputs =
    _:
    let
      system = "SYSTEM";
      source = builtins.path {
        path = ./.;
        name = "nu-nix-task-fixture";
      };
      buildSource = builtins.toFile "nu-nix-native-build-source" "built";
      builtOutput = builtins.derivation {
        inherit system;
        name = "nu-nix-native-build";
        builder = "builtin:fetchurl";
        url = "file://${buildSource}";
        outputHash = builtins.hashFile "sha256" buildSource;
        outputHashAlgo = "sha256";
        outputHashMode = "flat";
      };
      failedOutput = builtins.derivation {
        inherit system;
        name = "nu-nix-native-failure";
        builder = "builtin:fetchurl";
        url = "file://${buildSource}";
        outputHash = builtins.hashString "sha256" "wrong";
        outputHashAlgo = "sha256";
        outputHashMode = "flat";
      };
      task =
        {
          script,
          description,
          deps ? [ ],
          environment ? { },
        }:
        {
          type = "nu-nix-task";
          version = 2;
          inherit
            deps
            description
            ;
          action = {
            type = "nushell";
            environment = environment // {
              NU_NIX_CONTEXT = "${builtins.toFile "nu-nix-context" "context"}";
            };
            script = {
              type = "file";
              path = "${source}/${builtins.baseNameOf script}";
            };
            path = "";
          };
        };
    in
    {
      quoted."name.with.dots" = 42;

      nushell.${system} = {
        type = "nu-nix-interface";
        version = 1;
        modules.example = {
          type = "nu-nix-publication";
          version = 1;
          role = "module";
          package = "${source}";
          entrypoint = "main.nu";
          description = "Example generated module";
        };
        applications = { };
        plugins = { };
        exports = {
          add = {
            type = "nu-nix-export";
            version = 1;
            description = "Add two integers";
            arguments = [
              "left"
              "right"
            ];
            result = "collect";
            function = left: right: left + right;
          };
          select = {
            type = "nu-nix-export";
            version = 1;
            description = "Select a lazy value";
            arguments = [
              "name"
              "values"
            ];
            result = "lazy";
            function = name: values: values.${name};
          };
        };
      };

      tasks.${system} = {
        prepare = task {
          description = "Prepare the test fixture";
          script = ./prepare.nu;
        };
        main = task {
          description = "Run the requested task";
          deps = [
            "prepare"
            "realise"
          ];
          environment.NU_NIX_TASK_FROM_FLAKE = "configured";
          script = ./main.nu;
        };
        realise = {
          type = "nu-nix-task";
          version = 2;
          description = "Realise a Nix output";
          deps = [ ];
          action = {
            type = "realise";
            targets.output = "${builtins.toFile "nu-nix-task-output" "output"}";
          };
        };
        build = {
          type = "nu-nix-task";
          version = 2;
          description = "Build an unrealised derivation";
          deps = [ ];
          action = {
            type = "realise";
            targets.output = "${builtOutput}";
          };
        };
        failing-build = {
          type = "nu-nix-task";
          version = 2;
          description = "Fail while building a target";
          deps = [ ];
          action = {
            type = "realise";
            targets.broken = "${failedOutput}";
          };
        };
        after-failure = task {
          description = "Must be skipped after failure";
          deps = [ "failing-build" ];
          script = ./prepare.nu;
        };
        cycle-a = task {
          description = "Cycle fixture A";
          deps = [ "cycle-b" ];
          script = ./prepare.nu;
        };
        cycle-b = task {
          description = "Cycle fixture B";
          deps = [ "cycle-a" ];
          script = ./prepare.nu;
        };
        inline = {
          type = "nu-nix-task";
          version = 2;
          description = "Run inline source without a temporary file";
          deps = [ ];
          action = {
            type = "nushell";
            environment = { };
            path = "";
            script = {
              type = "inline";
              text = ''
                def main [argument: string] {
                  print "inline stdout"
                  print --stderr "inline stderr"
                  $"inline:($argument)(char nl)" | save --append $env.NU_NIX_TASK_TEST_LOG
                }
              '';
            };
          };
        };
        inline-failure = {
          type = "nu-nix-task";
          version = 2;
          description = "Preserve an inline task's exit status";
          deps = [ ];
          action = {
            type = "nushell";
            environment = { };
            path = "";
            script = {
              type = "inline";
              text = "exit 23";
            };
          };
        };
      };
    };
}
