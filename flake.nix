{
  description = "Nushell and Nix integration helpers";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system:
          f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.callPackage ./package { };
        nu-nix = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      });

      apps = forAllSystems (pkgs: {
        # `nix run github:cwd-k2/nu-nix` launches Nushell via the nu-bash wrapper.
        default = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/nu-bash";
          meta.description = "Launch Nushell via the nu-bash login-shell wrapper";
        };
      });

      nixosModules.default = import ./modules/nu-nix.nix;
      nixosModules.nu-nix = self.nixosModules.default;

      checks = forAllSystems (pkgs:
        let pkg = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        in {
          package = pkg;

          # Pure Nushell tests for `to nix` — no Nix evaluation, runs in sandbox.
          to-nix-tests = pkgs.runCommand "nu-nix-to-nix-tests"
            { buildInputs = [ pkgs.nushell ]; }
            ''
              cp ${./tests/test_to_nix.nu} test_to_nix.nu
              substituteInPlace test_to_nix.nu \
                --replace '../package/scripts/nu-nix/mod.nu' \
                          '${pkg}/share/nushell/nu-nix/mod.nu'
              nu test_to_nix.nu
              touch $out
            '';
        });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
