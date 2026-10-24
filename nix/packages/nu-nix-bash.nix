{
  bashInteractive,
  lib,
  nushell,
  writeShellApplication,
}:

writeShellApplication {
  name = "nu-nix-bash";
  text = ''
    bash="${bashInteractive}/bin/bash"
    nu="${nushell}/bin/nu"

    # Login-shell compatibility wrapper. Tools such as Zed, ssh, WSL
    # launchers, and nix may run the user's shell with POSIX snippets.
    # Keep those executions on bash.
    if [ "$#" -gt 0 ]; then
      exec "$bash" "$@"
    fi

    # Follow the usual interactive-shell convention: stdin and stderr must
    # be terminals. stdout may legitimately be redirected by the user.
    if [ -t 0 ] && [ -t 2 ]; then
      exec "$nu" --login
    fi

    exec "$bash"
  '';

  passthru.shellPath = "/bin/nu-nix-bash";

  meta = {
    description = "Login-shell compatibility launcher for Nushell";
    license = lib.licenses.mit;
    mainProgram = "nu-nix-bash";
    platforms = lib.platforms.linux;
  };
}
