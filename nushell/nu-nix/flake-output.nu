# Shared selection of a system-specific project output from a lazy flake value.

export def flake-system-output [
  reference: string,
  base_path: path,
  output_name: string,
  system: string,
]: nothing -> any {
  let outputs = (nix flake outputs $reference --base-path $base_path)
  let output = try { $outputs | get $output_name } catch {
    error make {msg: $"flake ($reference) does not define a ($output_name) output"}
  }
  try { $output | get $system } catch {
    error make {msg: $"flake ($reference) does not define ($output_name).($system)"}
  }
}
