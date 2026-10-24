# Flake-published Nushell roles and Nix functions.

use system.nu current-nix-system
use flake-output.nu flake-system-output

def flake-interface [reference: string, base_path: path, system: string]: nothing -> any {
  let selected = (flake-system-output $reference $base_path nushell $system)
  let interface_type = (try { $selected.type | nix collect } catch { null })
  let version = (try { $selected.version | nix collect } catch { null })
  if $interface_type != "nu-nix-interface" or $version != 1 {
    error make {msg: $"flake ($reference) has an unsupported Nushell interface schema"}
  }
  $selected
}

def export-descriptor [exports: any, name: string]: nothing -> any {
  let names = ($exports | nix attr names)
  if $name not-in $names {
    error make {msg: $"unknown Nix export `($name)`"}
  }
  let descriptor = ($exports | get $name)
  let descriptor_type = (try { $descriptor.type | nix collect } catch { null })
  let version = (try { $descriptor.version | nix collect } catch { null })
  if $descriptor_type != "nu-nix-export" or $version != 1 {
    error make {msg: $"Nix export `($name)` has an unsupported schema"}
  }
  let description = (try { $descriptor.description | nix collect } catch { null })
  if ($description | describe) != "string" {
    error make {msg: $"Nix export `($name)` description must be a string"}
  }
  let arguments = (try { $descriptor.arguments | nix collect } catch { null })
  if not (($arguments | describe) | str starts-with "list") or ($arguments | is-empty) {
    error make {msg: $"Nix export `($name)` arguments must be a non-empty list"}
  }
  if ($arguments | any {|argument|
    (($argument | describe) != "string") or (not ($argument =~ '^[A-Za-z_][A-Za-z0-9_-]*$'))
  }) {
    error make {msg: $"Nix export `($name)` argument names must be simple strings"}
  }
  if (($arguments | uniq | length) != ($arguments | length)) {
    error make {msg: $"Nix export `($name)` argument names must be unique"}
  }
  let result = (try { $descriptor.result | nix collect } catch { null })
  if $result not-in [lazy collect realise] {
    error make {msg: $"Nix export `($name)` has unsupported result policy ($result)"}
  }
  let function_type = (try { $descriptor.function | nix type } catch { null })
  if $function_type != "a function" {
    error make {msg: $"Nix export `($name)` function must be callable"}
  }
  $descriptor
}

def valid-entrypoint [entrypoint: string]: nothing -> bool {
  ($entrypoint | is-not-empty) and (
    $entrypoint
    | split row "/"
    | all {|component| $component =~ '^[A-Za-z0-9][A-Za-z0-9._+-]*$' }
  )
}

# List callable Nix functions published by a flake.
export def "nix export list" [
  --flake: string = "."
  --base-path: path = .
  --system: string
]: nothing -> table {
  let selected_system = ($system | default (current-nix-system))
  let interface = (flake-interface $flake $base_path $selected_system)
  let exports = (try { $interface.exports } catch { return [] })
  $exports
  | nix attr names
  | each {|name|
      let descriptor = (export-descriptor $exports $name)
      {
        name: $name
        description: ($descriptor.description | nix collect)
        arguments: ($descriptor.arguments | nix collect)
        result: ($descriptor.result | nix collect)
      }
    }
}

# Inspect one callable Nix export without forcing its function result.
export def "nix export inspect" [
  name: string
  --flake: string = "."
  --base-path: path = .
  --system: string
]: nothing -> record {
  let selected_system = ($system | default (current-nix-system))
  let interface = (flake-interface $flake $base_path $selected_system)
  let exports = (try { $interface.exports } catch {
    error make {msg: $"flake ($flake) does not publish callable Nix exports"}
  })
  let descriptor = (export-descriptor $exports $name)
  {
    name: $name
    description: ($descriptor.description | nix collect)
    arguments: ($descriptor.arguments | nix collect)
    result: ($descriptor.result | nix collect)
  }
}

# Call a Nix function published by a flake.
export def "nix export call" [
  name: string
  --flake: string = "."
  --base-path: path = .
  --system: string
  --arguments: list<any> = []
]: nothing -> any {
  let selected_system = ($system | default (current-nix-system))
  let interface = (flake-interface $flake $base_path $selected_system)
  let exports = (try { $interface.exports } catch {
    error make {msg: $"flake ($flake) does not publish callable Nix exports"}
  })
  let descriptor = (export-descriptor $exports $name)
  let declared_arguments = ($descriptor.arguments | nix collect)
  if ($arguments | length) != ($declared_arguments | length) {
    error make {
      msg: $"Nix export `($name)` expects ($declared_arguments | length) arguments; got ($arguments | length)"
    }
  }
  let first_argument = ($arguments | first)
  let remaining_arguments = ($arguments | skip 1)
  let value = ($descriptor.function | nix call $first_argument ...$remaining_arguments)
  match ($descriptor.result | nix collect) {
    "lazy" => $value
    "collect" => ($value | nix collect)
    "realise" => ($value | nix realise --details)
    $policy => { error make {msg: $"Nix export `($name)` has unsupported result policy ($policy)"} }
  }
}

# List Nushell module, application, and plugin publications from a flake.
export def "nix publication list" [
  --flake: string = "."
  --base-path: path = .
  --system: string
]: nothing -> table {
  let selected_system = ($system | default (current-nix-system))
  let interface = (flake-interface $flake $base_path $selected_system)
  publication-list $interface
}

def publication-inventory [interface: any]: nothing -> table {
  [
    {role: module, field: modules}
    {role: application, field: applications}
    {role: plugin, field: plugins}
  ]
  | each {|collection|
      let publications = (try { $interface | get $collection.field } catch { return [] })
      $publications
      | nix attr names
      | each {|name|
          {
            role: $collection.role
            name: $name
          }
        }
    }
  | flatten
}

def publication-list [interface: any]: nothing -> table {
  publication-inventory $interface
  | each {|item|
      let publication = (publication-descriptor $interface $item.role $item.name)
      inspect-publication $publication $item.role $item.name
      | reject package
    }
}

def publication-descriptor [
  interface: any,
  role: string,
  name: string,
]: nothing -> any {
  if $role not-in [module application plugin] {
    error make {msg: $"unsupported publication role `($role)`"}
  }
  let collection = ($interface | get $"($role)s")
  if $name not-in ($collection | nix attr names) {
    error make {msg: $"unknown ($role) publication `($name)`"}
  }
  let publication = ($collection | get $name)
  if ($publication.type | nix collect) != "nu-nix-publication" or ($publication.version | nix collect) != 1 {
    error make {msg: $"publication `($name)` has an unsupported schema"}
  }
  if ($publication.role | nix collect) != $role {
    error make {msg: $"publication `($name)` declares the wrong role"}
  }
  let description = (try { $publication.description | nix collect } catch { null })
  if ($description | describe) != "string" {
    error make {msg: $"publication `($name)` description must be a string"}
  }
  let entrypoint = (try { $publication.entrypoint | nix collect } catch { null })
  if ($entrypoint | describe) != "string" or not (valid-entrypoint $entrypoint) {
    error make {
      msg: $"publication `($name)` entrypoint must be a non-empty package-relative path"
    }
  }
  let package_type = (try { $publication.package | nix type } catch { null })
  if not (($package_type | default "") | str starts-with "a string") {
    error make {msg: $"publication `($name)` package must be a contextual Nix string"}
  }
  $publication
}

def inspect-publication [publication: any, role: string, name: string]: nothing -> record {
  {
    role: $role
    name: $name
    description: ($publication.description | nix collect)
    entrypoint: ($publication.entrypoint | nix collect)
    package: $publication.package
  }
}

def resolve-publication [publication: any, role: string, name: string]: nothing -> record {
  let details = ($publication.package | nix realise --details)
  if ($details.physicalPaths | length) != 1 {
    error make {msg: $"publication `($name)` package must realise to exactly one path"}
  }
  let root = ($details.physicalPaths | first)
  let entrypoint = ($publication.entrypoint | nix collect)
  let resolved = ($root | path join $entrypoint)
  if not ($resolved | path exists) {
    error make {msg: $"publication `($name)` entrypoint does not exist: ($resolved)"}
  }
  {role: $role, name: $name, root: $root, entrypoint: $resolved}
}

# Inspect one publication without realising its package.
export def "nix publication inspect" [
  role: string
  name: string
  --flake: string = "."
  --base-path: path = .
  --system: string
]: nothing -> record {
  let selected_system = ($system | default (current-nix-system))
  let interface = (flake-interface $flake $base_path $selected_system)
  let publication = (publication-descriptor $interface $role $name)
  inspect-publication $publication $role $name
}

# Realise a publication and return its physical entrypoint.
export def "nix publication resolve" [
  role: string
  name: string
  --flake: string = "."
  --base-path: path = .
  --system: string
]: nothing -> record {
  let selected_system = ($system | default (current-nix-system))
  let interface = (flake-interface $flake $base_path $selected_system)
  let publication = (publication-descriptor $interface $role $name)
  resolve-publication $publication $role $name
}

# Check all publication descriptors, optionally realising their entrypoints.
export def "nix publication check" [
  --flake: string = "."
  --base-path: path = .
  --system: string
  --realise
]: nothing -> table {
  let selected_system = ($system | default (current-nix-system))
  let interface = (flake-interface $flake $base_path $selected_system)
  publication-inventory $interface
  | each {|item|
      try {
        let publication = (publication-descriptor $interface $item.role $item.name)
        if $realise {
          resolve-publication $publication $item.role $item.name | ignore
        } else {
          inspect-publication $publication $item.role $item.name | ignore
        }
        {role: $item.role, name: $item.name, status: "ok", error: null}
      } catch {|error|
        {role: $item.role, name: $item.name, status: "error", error: $error.msg}
      }
    }
}
