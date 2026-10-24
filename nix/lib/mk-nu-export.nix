{ lib }:

{
  function,
  description ? "",
  arguments ? [ ],
  result ? "lazy",
}:

assert lib.assertMsg (builtins.isFunction function) "Nushell exports require a Nix function";
assert lib.assertMsg (builtins.isString description) "Nushell export descriptions must be strings";
assert lib.assertMsg (builtins.isList arguments) "Nushell export arguments must be a list";
assert lib.assertMsg (arguments != [ ]) "Nushell exports require at least one argument";
assert lib.assertMsg (lib.all (
  argument: builtins.isString argument && builtins.match "[A-Za-z_][A-Za-z0-9_-]*" argument != null
) arguments) "Nushell export argument names must be simple strings";
assert lib.assertMsg (
  builtins.length arguments == builtins.length (lib.unique arguments)
) "Nushell export argument names must be unique";
assert lib.assertMsg (builtins.elem result [
  "lazy"
  "collect"
  "realise"
]) "Nushell export result must be lazy, collect, or realise";
{
  type = "nu-nix-export";
  version = 1;
  inherit
    arguments
    description
    function
    result
    ;
}
