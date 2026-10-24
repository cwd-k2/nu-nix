{
  outputs = _: {
    nushell.SYSTEM = {
      type = "nu-nix-interface";
      version = 1;
      modules.escaped = {
        type = "nu-nix-publication";
        version = 1;
        role = "module";
        package = "${builtins.toFile "nu-nix-malformed-publication" "invalid"}";
        entrypoint = "../outside.nu";
        description = "Invalid package-relative entrypoint";
      };
      applications.empty = {
        type = "nu-nix-publication";
        version = 1;
        role = "application";
        package = "${builtins.toFile "nu-nix-empty-entrypoint" "invalid"}";
        entrypoint = "";
        description = "Invalid empty entrypoint";
      };
      plugins = { };
      exports.invalid = {
        type = "nu-nix-export";
        version = 1;
        description = "Invalid zero-argument export";
        arguments = [ ];
        result = "lazy";
        function = value: value;
      };
      exports.notFunction = {
        type = "nu-nix-export";
        version = 1;
        description = "Invalid function export";
        arguments = [ "value" ];
        result = "lazy";
        function = 42;
      };
    };
    tasks.SYSTEM = {
      old-version = {
        type = "nu-nix-task";
        version = 1;
        description = "Removed advisory capability schema";
        deps = [ ];
        action = {
          type = "realise";
          targets.output = "${builtins.toFile "nu-nix-old-task" "old"}";
        };
      };
      prepare = {
        type = "nu-nix-task";
        version = 2;
        description = "Must not run before the plan is valid";
        deps = [ ];
        action = {
          type = "nushell";
          environment = { };
          path = "";
          script = {
            type = "inline";
            text = ''"ran" | save $env.NU_NIX_MALFORMED_LOG'';
          };
        };
      };
      malformed = {
        type = "nu-nix-task";
        version = 2;
        description = "Invalid root action";
        deps = [ "prepare" ];
        action.type = "unknown";
      };
      bad-path = {
        type = "nu-nix-task";
        version = 2;
        description = "Invalid reserved PATH fixture";
        deps = [ ];
        action = {
          type = "nushell";
          environment.PATH = "/unexpected";
          path = "";
          script = {
            type = "inline";
            text = "print invalid";
          };
        };
      };
      bad-script-path = {
        type = "nu-nix-task";
        version = 2;
        description = "Invalid store-relative script path fixture";
        deps = [ ];
        action = {
          type = "nushell";
          environment = { };
          path = "";
          script = {
            type = "file";
            path = "${builtins.toFile "nu-nix-malformed-script" "print invalid"}/../outside.nu";
          };
        };
      };
    };
  };
}
