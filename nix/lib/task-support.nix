{ lib }:

{
  mkTask =
    {
      description,
      deps,
      action,
    }:
    assert lib.assertMsg (builtins.isString description) "Task descriptions must be strings";
    assert lib.assertMsg (
      builtins.isList deps && lib.all builtins.isString deps
    ) "Task dependencies must be task names";
    {
      type = "nu-nix-task";
      version = 2;
      inherit
        action
        deps
        description
        ;
    };
}
