# Run with the nu-nix plugin and module already loaded.

let project = (nix eval '{
  name = "native-values";
  packages = {
    stable = { version = "1.0"; enabled = true; };
    edge = { version = "2.0"; enabled = false; };
  };
  expensive = throw "this remains lazy";
}')

print $"outer type: ($project | nix type)"
print $"attributes: ($project | nix attr names | str join ', ')"

$project.packages
| nix attr names
| each {|name|
    let package = ($project.packages | get $name)
    {
      name: $name
      version: ($package.version | nix collect)
      enabled: ($package.enabled | nix collect)
    }
  }
| table

# Only this small subtree is forced. `$project.expensive` is never evaluated.
$project.packages.stable | nix collect

# A fragment can select a nested output without collecting the entire flake.
# Discover an available system instead of baking one architecture into the script.
let systems = (nix flake outputs '.#formatter' | nix attr names)
let formatter = (nix flake outputs $".#formatter.($systems.0)")
print $"formatter output type: ($formatter | nix type)"
