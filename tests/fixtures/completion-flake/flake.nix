{
  outputs = _: {
    packages = {
      x86_64-linux = {
        alpha = null;
        beta = null;
        scope.gamma = null;
      };
      aarch64-linux = {
        alpha = null;
        beta = null;
        scope.gamma = null;
      };
    };
    devShells = {
      x86_64-linux.development = null;
      aarch64-linux.development = null;
    };
  };
}
