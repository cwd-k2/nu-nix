# Nix platform identity shared by tasks and completion.

export def current-nix-system []: nothing -> string {
  # The supported targets map directly from Nushell's Linux host identity.
  # Project commands expose --system for emulation and foreign-system plans;
  # avoid an evaluator call here because changing its policy invalidates handles.
  $"($nu.os-info.arch)-($nu.os-info.name)"
}
