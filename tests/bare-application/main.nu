def main [value: string] {
  {value: $value, configured: $env.NU_NIX_BARE_TEST} | to json --raw
}
