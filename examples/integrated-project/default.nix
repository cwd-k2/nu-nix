{ pkgs, nu-nix }:

let
  system = pkgs.stdenv.hostPlatform.system;
  contextModule = nu-nix.lib.mkNuModuleFromValue {
    inherit pkgs;
    name = "example-context";
    values = {
      host = "example-host";
      features = [
        "generated-data"
        "generated-environment"
      ];
    };
  };
  environmentModule = nu-nix.lib.mkNuEnvModule {
    inherit pkgs;
    name = "example-environment";
    variables = {
      EDITOR = "nvim";
      EXAMPLE_PATH = [
        "/existing"
        "/shared"
      ];
    };
    prependPath.EXAMPLE_PATH = [
      "/generated"
      "/shared"
    ];
  };
  application = nu-nix.lib.mkNuApplication {
    inherit pkgs;
    name = "nu-nix-generated-example";
    src = ./app;
    runtimeInputs = [ pkgs.hello ];
    nuLibraries = [
      nu-nix.packages.${system}.default
      contextModule
      environmentModule
    ];
    environment.NU_NIX_APPLICATION_TEST = "from-nix";
  };
  published = {
    modules.context = {
      package = contextModule;
      entrypoint = "share/nushell/example-context/mod.nu";
      description = "Generated Nushell constants used by the example application";
    };
    applications.greeter = {
      package = application;
      entrypoint = "bin/nu-nix-generated-example";
      description = "Nushell application with Nix-generated data and environment";
    };
    plugins.nix = {
      package = nu-nix.packages.${system}.native-plugin;
      entrypoint = "bin/nu_plugin_nix";
      description = "Native lazy Nix value bridge";
    };
  };
  nuSession = nu-nix.lib.mkNuSession {
    inherit pkgs;
    name = "nu-nix-integrated-session";
    inherit (published) modules applications plugins;
    packages = [ pkgs.jq ];
  };
  commonTask = {
    inherit pkgs;
    environment.NU_NIX_EXAMPLE_REPORT = ".nu-nix-example/report.json";
  };
in
{
  inherit
    application
    published
    contextModule
    environmentModule
    nuSession
    ;

  tasks = {
    runtime = nu-nix.lib.mkDerivationTask {
      inherit pkgs;
      description = "Realise the application's cacheable runtime";
      targets = {
        inherit application;
        inherit (pkgs) jq;
      };
    };

    prepare = nu-nix.lib.mkNuTask (
      commonTask
      // {
        description = "Run the packaged application and save a report";
        deps = [ "runtime" ];
        runtimeInputs = [
          application
          pkgs.jq
        ];
        script = ./tasks/prepare.nu;
      }
    );

    check = nu-nix.lib.mkNuTask (
      commonTask
      // {
        description = "Validate the generated report";
        deps = [ "prepare" ];
        script = ./tasks/check.nu;
      }
    );

    show = nu-nix.lib.mkNuTask (
      commonTask
      // {
        description = "Print the report after validating it";
        deps = [ "check" ];
        script = ./tasks/show.nu;
      }
    );
  };
}
