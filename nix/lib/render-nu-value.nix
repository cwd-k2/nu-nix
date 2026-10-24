{ lib }:

value:

let
  controlCodes = lib.range 1 31;
  jsonUnicodeEscapes = map (
    code: "\\u${lib.fixedWidthString 4 "0" (lib.toHexString code)}"
  ) controlCodes;
  nuUnicodeEscapes = map (code: "\\u{${lib.toHexString code}}") controlCodes;
  renderString =
    value': lib.replaceStrings jsonUnicodeEscapes nuUnicodeEscapes (builtins.toJSON value');
  render =
    value':
    if builtins.isPath value' then
      renderString (toString value')
    else if builtins.isList value' then
      "[${lib.concatMapStringsSep ", " render value'}]"
    else if builtins.isAttrs value' then
      let
        renderEntry = name: nested: "${renderString name}: ${render nested}";
      in
      "{${lib.concatStringsSep ", " (lib.mapAttrsToList renderEntry value')}}"
    else if
      builtins.isString value'
      || builtins.isBool value'
      || builtins.isInt value'
      || builtins.isFloat value'
      || value' == null
    then
      if builtins.isString value' then renderString value' else builtins.toJSON value'
    else
      throw "Cannot render ${builtins.typeOf value'} as a Nushell value";
in
render value
