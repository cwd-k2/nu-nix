{ pkgs, nu-nix }:

let
  catalog = [
    {
      name = "alpha";
      enabled = true;
      owner = "platform";
    }
    {
      name = "beta";
      enabled = false;
      owner = "research";
    }
    {
      name = "gamma";
      enabled = true;
      owner = "platform";
    }
  ];
  catalogModule = nu-nix.lib.mkNuModuleFromValue {
    inherit pkgs;
    name = "project-catalog";
    values = {
      project = "build-pipeline";
      items = catalog;
    };
  };
  reportModule = nu-nix.lib.mkNuModule {
    inherit pkgs;
    name = "report-tools";
    src = ./module;
  };
  report = nu-nix.lib.runNuCommand {
    inherit pkgs;
    name = "nu-nix-build-pipeline-report";
    scriptFile = ./build/report.nu;
    nuLibraries = [
      catalogModule
      reportModule
    ];
    derivationArgs.REPORT_VERSION = "1";
  };
  taskEnvironment = {
    NU_NIX_PIPELINE_REPORT = "${report}/report.json";
    NU_NIX_PIPELINE_PUBLISHED = ".nu-nix-example/published-report.json";
  };
in
{
  inherit
    catalogModule
    report
    reportModule
    ;

  tasks = {
    build = nu-nix.lib.mkDerivationTask {
      inherit pkgs;
      description = "Build the report with Nushell inside Nix";
      targets.default = report;
    };

    publish = nu-nix.lib.mkNuTask {
      inherit pkgs;
      description = "Publish the immutable report into the working tree";
      deps = [ "build" ];
      environment = taskEnvironment;
      script = ./tasks/publish.nu;
    };

    check = nu-nix.lib.mkNuTask {
      inherit pkgs;
      description = "Validate the locally published report";
      deps = [ "publish" ];
      environment = taskEnvironment;
      script = ./tasks/check.nu;
    };
  };

  selectItem = name: pkgs.lib.findFirst (item: item.name == name) null catalog;
}
