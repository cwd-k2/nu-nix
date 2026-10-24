{
  lib,
  flake-parts-lib,
  ...
}:

let
  inherit (flake-parts-lib) mkPerSystemOption;
  validPathComponent = component: builtins.match "[A-Za-z0-9][A-Za-z0-9._+-]*" component != null;
  validEntrypoint =
    entrypoint: entrypoint != "" && lib.all validPathComponent (lib.splitString "/" entrypoint);
  validExportArgument = argument: builtins.match "[A-Za-z_][A-Za-z0-9_-]*" argument != null;
  publicationType =
    role:
    lib.types.submodule {
      options = {
        type = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default = "nu-nix-publication";
        };
        version = lib.mkOption {
          type = lib.types.int;
          readOnly = true;
          default = 1;
        };
        role = lib.mkOption {
          type = lib.types.enum [ role ];
          readOnly = true;
          default = role;
        };
        package = lib.mkOption {
          type = lib.types.package;
          apply = toString;
        };
        entrypoint = lib.mkOption {
          type = lib.types.addCheck lib.types.str validEntrypoint;
          description = "Non-empty package-relative entrypoint for the published Nushell role";
        };
        description = lib.mkOption {
          type = lib.types.str;
          default = "";
        };
      };
    };
  taskType = lib.types.submodule {
    options = {
      type = lib.mkOption {
        type = lib.types.enum [ "nu-nix-task" ];
      };
      version = lib.mkOption {
        type = lib.types.enum [ 2 ];
      };
      description = lib.mkOption {
        type = lib.types.str;
      };
      deps = lib.mkOption {
        type = lib.types.listOf lib.types.str;
      };
      action = lib.mkOption {
        type = lib.types.attrs;
        description = "Task action validated by the nu-nix task runner";
      };
    };
  };
  exportType = lib.types.submodule {
    options = {
      type = lib.mkOption {
        type = lib.types.enum [ "nu-nix-export" ];
        default = "nu-nix-export";
      };
      version = lib.mkOption {
        type = lib.types.enum [ 1 ];
        default = 1;
      };
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
      arguments = lib.mkOption {
        type = lib.types.addCheck (lib.types.listOf lib.types.str) (
          arguments:
          arguments != [ ]
          && lib.all validExportArgument arguments
          && builtins.length arguments == builtins.length (lib.unique arguments)
        );
      };
      result = lib.mkOption {
        type = lib.types.enum [
          "lazy"
          "collect"
          "realise"
        ];
        default = "lazy";
      };
      function = lib.mkOption {
        type = lib.types.addCheck lib.types.raw builtins.isFunction;
      };
    };
  };
in
{
  options.perSystem = mkPerSystemOption (_: {
    options = {
      nushell = {
        type = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default = "nu-nix-interface";
        };
        version = lib.mkOption {
          type = lib.types.int;
          readOnly = true;
          default = 1;
        };
        modules = lib.mkOption {
          type = lib.types.attrsOf (publicationType "module");
          default = { };
        };
        applications = lib.mkOption {
          type = lib.types.attrsOf (publicationType "application");
          default = { };
        };
        plugins = lib.mkOption {
          type = lib.types.attrsOf (publicationType "plugin");
          default = { };
        };
        exports = lib.mkOption {
          type = lib.types.lazyAttrsOf exportType;
          default = { };
        };
      };

      tasks = lib.mkOption {
        type = lib.types.attrsOf taskType;
        default = { };
        description = "Nix-backed Nushell project tasks";
      };
    };
  });

  config.transposition = {
    nushell = { };
    tasks = { };
  };
}
