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
in
{
  inherit application contextModule environmentModule;
}
