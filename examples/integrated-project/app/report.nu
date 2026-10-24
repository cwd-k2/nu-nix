export def project-report [name: string, message: string] {
  {
    greeting: $"($message) ($name)"
    nix: ({enabled: true} | to nix)
    external: (^hello | str trim)
    configured: $env.NU_NIX_APPLICATION_TEST
    host: $host
    features: $features
    editor: $env.EDITOR
    example_path: $env.EXAMPLE_PATH
  }
}
