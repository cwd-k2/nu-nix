{
  lib,
  makeWrapper,
  nuNixPackage,
  nushell,
  runCommand,
}:

{
  name,
  src,
  entrypoint ? "main.nu",
  runtimeInputs ? [ ],
  nuLibraries ? [ nuNixPackage ],
  nuLibDirs ? [ ],
  environment ? { },
  extraWrapperArgs ? [ ],
  meta ? { },
  passthru ? { },
}:

let
  support = import ./builder-support.nix { inherit lib; };
  sourceDirectory = "${src}/.";
  includePath = support.mkNuLibraryPath { inherit nuLibraries nuLibDirs; };
  invalidEnvironmentNames = builtins.filter (variable: !support.validEnvironmentName variable) (
    lib.attrNames environment
  );
  invalidEnvironmentValues = builtins.filter (
    variable: !support.validEnvironmentValue environment.${variable}
  ) (lib.attrNames environment);
  environmentArgs = lib.concatLists (
    lib.mapAttrsToList (variable: value: [
      "--set"
      variable
      value
    ]) environment
  );
  wrapperArgs = [
    "--add-flags"
    "--no-config-file"
  ]
  ++ lib.optionals (includePath != null) [
    "--add-flags"
    "--include-path"
    "--add-flags"
    includePath
  ]
  ++ lib.optionals (runtimeInputs != [ ]) [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath runtimeInputs)
  ]
  ++ environmentArgs
  ++ extraWrapperArgs;
in
assert lib.assertMsg (support.validName name)
  "Nushell application names must be safe path basenames; invalid name: ${builtins.toJSON name}";
assert lib.assertMsg (support.validRelativePath entrypoint)
  "Nushell application entrypoints must be safe relative paths; invalid entrypoint: ${builtins.toJSON entrypoint}";
assert lib.assertMsg (invalidEnvironmentNames == [ ])
  "Nushell application environment variable names must use shell-compatible identifiers; invalid names: ${lib.concatStringsSep ", " invalidEnvironmentNames}";
assert lib.assertMsg (invalidEnvironmentValues == [ ])
  "Nushell application environment values must be strings, paths, or derivations; invalid variables: ${lib.concatStringsSep ", " invalidEnvironmentValues}";
runCommand name
  {
    nativeBuildInputs = [ makeWrapper ];
    inherit passthru;
    meta = {
      mainProgram = name;
    }
    // meta;
  }
  ''
    mkdir -p "$out/bin" "$out/libexec/${name}"
    cp -R ${lib.escapeShellArg sourceDirectory} "$out/libexec/${name}/"

    if [[ ! -f "$out/libexec/${name}/${entrypoint}" ]]; then
      echo "Nushell application ${name} does not provide ${entrypoint}" >&2
      exit 1
    fi

    makeWrapper ${lib.escapeShellArg (lib.getExe nushell)} "$out/bin/${name}" \
      ${lib.escapeShellArgs wrapperArgs} \
      --add-flags "$out/libexec/${name}/${entrypoint}"
  ''
