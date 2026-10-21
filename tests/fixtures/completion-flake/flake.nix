{
  outputs = { ... }: {
    packages = {
      x86_64-linux = {
        alpha = null;
        beta = null;
      };
      aarch64-linux = {
        alpha = null;
        beta = null;
      };
    };
    devShells = {
      x86_64-linux.development = null;
      aarch64-linux.development = null;
    };
  };
}
