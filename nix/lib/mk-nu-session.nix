{
  lib,
  makeWrapper,
  nushell,
  runCommand,
  writeText,
}:

{
  name,
  modules ? { },
  plugins ? { },
  applications ? { },
  packages ? [ ],
  meta ? { },
  passthru ? { },
}:

let
  support = import ./builder-support.nix { inherit lib; };
  componentNames = builtins.attrNames;
  packageOf = component: component.package or null;
  entrypointOf = component: component.entrypoint or "";
  validPackage =
    package: lib.isDerivation package || (builtins.isString package && builtins.hasContext package);
  invalidNames = lib.concatLists (
    map
      (
        components:
        builtins.filter (componentName: !support.validName componentName) (componentNames components)
      )
      [
        modules
        plugins
        applications
      ]
  );
  invalidComponents =
    role: components:
    builtins.filter (
      componentName:
      let
        component = components.${componentName};
      in
      !(builtins.isAttrs component)
      || !validPackage (packageOf component)
      || !support.validRelativePath (entrypointOf component)
      || (component ? type && component.type != "nu-nix-publication")
      || (component ? version && component.version != 1)
      || (component ? role && component.role != role)
    ) (componentNames components);
  invalidModules = invalidComponents "module" modules;
  invalidPlugins = invalidComponents "plugin" plugins;
  invalidApplications = invalidComponents "application" applications;
  invalidPackages = builtins.filter (package: !validPackage package) packages;
  output = builtins.placeholder "out";
  moduleCommands = lib.concatMapStringsSep "\n" (
    componentName:
    let
      component = modules.${componentName};
      source = "${packageOf component}/${entrypointOf component}";
      entrypointName = builtins.baseNameOf (entrypointOf component);
    in
    if entrypointName == "mod.nu" then
      ''
        module_source=${lib.escapeShellArg (builtins.dirOf source)}
        if [[ ! -f "$module_source/mod.nu" ]]; then
          echo "Nushell module ${componentName} does not provide mod.nu at $module_source" >&2
          exit 1
        fi
        ln -s "$module_source" "$out/share/nushell/modules/${componentName}"
      ''
    else
      ''
        module_source=${lib.escapeShellArg source}
        if [[ ! -f "$module_source" ]]; then
          echo "Nushell module ${componentName} does not exist at $module_source" >&2
          exit 1
        fi
        ln -s "$module_source" "$out/share/nushell/modules/${componentName}.nu"
      ''
  ) (componentNames modules);
  pluginChecks = lib.concatMapStringsSep "\n" (
    componentName:
    let
      component = plugins.${componentName};
      entrypoint = "${packageOf component}/${entrypointOf component}";
    in
    ''
      if [[ ! -x ${lib.escapeShellArg entrypoint} ]]; then
        echo "Nushell plugin ${componentName} is not executable: ${entrypoint}" >&2
        exit 1
      fi
    ''
  ) (componentNames plugins);
  applicationChecks = lib.concatMapStringsSep "\n" (
    componentName:
    let
      component = applications.${componentName};
      entrypoint = "${packageOf component}/${entrypointOf component}";
    in
    ''
      if [[ ! -e ${lib.escapeShellArg entrypoint} ]]; then
        echo "Nushell application ${componentName} does not exist at ${entrypoint}" >&2
        exit 1
      fi
      if [[ ! -x ${lib.escapeShellArg entrypoint} ]]; then
        echo "Nushell application ${componentName} is not executable: ${entrypoint}" >&2
        exit 1
      fi
      ln -s ${lib.escapeShellArg entrypoint} \
        "$out/share/nushell/session/bin/${componentName}"
    ''
  ) (componentNames applications);
  manifestEntries =
    components:
    lib.mapAttrsToList (componentName: component: {
      name = componentName;
      package = toString (packageOf component);
      entrypoint = entrypointOf component;
    }) components;
  manifest = {
    version = 1;
    inherit name;
    modules = manifestEntries modules;
    plugins = manifestEntries plugins;
    applications = manifestEntries applications;
    packages = map toString packages;
  };
  manifestFile = writeText "${name}-manifest.json" (builtins.toJSON manifest);
  pluginFlags = lib.concatMap (
    componentName:
    let
      component = plugins.${componentName};
    in
    [
      "--add-flags"
      "--plugins"
      "--add-flags"
      "${packageOf component}/${entrypointOf component}"
    ]
  ) (componentNames plugins);
  moduleFlags = lib.optionals (modules != { }) [
    "--add-flags"
    "--include-path"
    "--add-flags"
    "${output}/share/nushell/modules"
  ];
  runtimePath = lib.concatStringsSep ":" (
    lib.optionals (applications != { }) [ "${output}/share/nushell/session/bin" ]
    ++ lib.optionals (packages != [ ]) [ (lib.makeBinPath packages) ]
  );
  pathFlags = lib.optionals (runtimePath != "") [
    "--prefix"
    "PATH"
    ":"
    runtimePath
  ];
in
assert lib.assertMsg (support.validName name)
  "Nushell session names must be safe path basenames; invalid name: ${builtins.toJSON name}";
assert lib.assertMsg (invalidNames == [ ])
  "Nushell session module, plugin, and application names must be safe path basenames; invalid names: ${lib.concatStringsSep ", " invalidNames}";
assert lib.assertMsg (invalidModules == [ ])
  "Nushell session modules must be component specifications with derivations or contextual packages and non-empty relative entrypoints; invalid modules: ${lib.concatStringsSep ", " invalidModules}";
assert lib.assertMsg (invalidPlugins == [ ])
  "Nushell session plugins must be component specifications with derivations or contextual packages and non-empty relative entrypoints; invalid plugins: ${lib.concatStringsSep ", " invalidPlugins}";
assert lib.assertMsg (invalidApplications == [ ])
  "Nushell session applications must be component specifications with derivations or contextual packages and non-empty relative entrypoints; invalid applications: ${lib.concatStringsSep ", " invalidApplications}";
assert lib.assertMsg (
  invalidPackages == [ ]
) "Nushell session packages must be derivations or contextual strings";
runCommand name
  {
    nativeBuildInputs = [ makeWrapper ];
    passthru = passthru // {
      nushellSession = manifest;
    };
    meta = {
      mainProgram = name;
    }
    // meta;
  }
  ''
    mkdir -p \
      "$out/bin" \
      "$out/share/nushell/session/bin" \
      "$out/share/nushell/modules"

    ${moduleCommands}
    ${pluginChecks}
    ${applicationChecks}

    ln -s ${manifestFile} \
      "$out/share/nushell/session/manifest.json"

    makeWrapper ${lib.escapeShellArg (lib.getExe nushell)} "$out/bin/${name}" \
      ${lib.escapeShellArgs (moduleFlags ++ pluginFlags ++ pathFlags)}
  ''
