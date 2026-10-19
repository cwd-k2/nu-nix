{ lib }:

value:

let
  render =
    value':
    if builtins.isPath value' then
      builtins.toJSON (toString value')
    else if builtins.isList value' then
      "[${lib.concatMapStringsSep ", " render value'}]"
    else if builtins.isAttrs value' then
      let
        renderEntry = name: nested: "${builtins.toJSON name}: ${render nested}";
      in
      "{${lib.concatStringsSep ", " (lib.mapAttrsToList renderEntry value')}}"
    else if
      builtins.isString value'
      || builtins.isBool value'
      || builtins.isInt value'
      || builtins.isFloat value'
      || value' == null
    then
      builtins.toJSON value'
    else
      throw "Cannot render ${builtins.typeOf value'} as a Nushell value";
in
render value
