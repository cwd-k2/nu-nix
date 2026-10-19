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
  recordSeparator = builtins.fromJSON ''"\u001e"'';
  libraryDirectories = map (package: "${package}/share/nushell") nuLibraries ++ nuLibDirs;
  includePath = lib.concatStringsSep recordSeparator libraryDirectories;
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
    cp -R ${src}/. "$out/libexec/${name}/"

    if [[ ! -f "$out/libexec/${name}/${entrypoint}" ]]; then
      echo "Nushell application ${name} does not provide ${entrypoint}" >&2
      exit 1
    fi

    makeWrapper ${lib.getExe nushell} "$out/bin/${name}" \
      ${lib.escapeShellArgs wrapperArgs} \
      --add-flags "$out/libexec/${name}/${entrypoint}"
  ''
