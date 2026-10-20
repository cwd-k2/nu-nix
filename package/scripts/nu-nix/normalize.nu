# Pure transformations from Nix JSON schemas to pipeline-friendly Nu values.
# Keeping these free of process execution makes schema behavior easy to test.

export def normalize-build []: any -> table {
  $in
  | each {|result|
      $result.outputs
      | transpose output path
      | insert drvPath $result.drvPath
    }
  | flatten
}

export def normalize-search []: record -> table {
  $in
  | transpose attr info
  | each {|result| $result.info | insert attr $result.attr }
}

export def normalize-path-info []: record -> table {
  $in
  | transpose path info
  | each {|result| $result.info | insert path $result.path }
}

export def normalize-derivations []: record -> table {
  $in
  | transpose drv info
  | each {|result| $result.info | insert drv $result.drv }
}

export def normalize-dev-environment []: record -> table {
  $in.variables
  | transpose name info
  | each {|result| $result.info | insert name $result.name }
}

export def normalize-profile []: record -> table {
  $in.elements
  | transpose name info
  | each {|result| $result.info | insert name $result.name }
}

export def normalize-dev-activation []: record -> record {
  let protected = [
    "HOME" "USER" "LOGNAME" "SHELL" "PWD" "OLDPWD" "SHLVL" "_"
    "TMP" "TEMP" "TMPDIR" "TEMPDIR" "NIX_BUILD_TOP"
  ]
  let variables = ($in.variables | transpose name info)
  let applicable = ($variables
    | where {|variable|
        $variable.info.type == "exported" and ($variable.name not-in $protected)
      })
  let updates = ($applicable | reduce --fold {} {|variable, result|
    let value = if $variable.name == "PATH" {
      $variable.info.value | split row (char esep) | where { not ($in | is-empty) }
    } else {
      $variable.info.value
    }
    $result | insert $variable.name $value
  })

  {
    updates: $updates
    skipped: ($variables
      | where {|variable|
          $variable.info.type != "exported" or ($variable.name in $protected)
        }
      | select name
      | get name)
  }
}

def is-record [value: any]: nothing -> bool {
  $value | describe | str starts-with "record"
}

def is-system [value: string]: nothing -> bool {
  $value =~ '^[A-Za-z0-9_]+-(linux|darwin|freebsd|netbsd|openbsd)$'
}

def flake-leaf [path: list<string>, value: any]: nothing -> record {
  let output = ($path | first)
  let tail = ($path | skip 1)
  let system = ($tail | where {|part| is-system $part } | first | default null)
  let names = if $system == null {
    $tail
  } else {
    $tail | where {|part| $part != $system }
  }
  let record_value = if (is-record $value) { $value } else { {} }

  {
    type: $output
    system: $system
    name: (if ($names | is-empty) { null } else { $names | str join "." })
    path: ($path | str join ".")
    kind: ($record_value.type? | default null)
    description: ($record_value.description? | default "")
    raw: $value
  }
}

def walk-flake [path: list<string>, value: any]: nothing -> list<any> {
  let traversable = (is-record $value) and ("type" not-in ($value | columns)) and (not ($value | is-empty))
  if $traversable {
    $value
    | transpose name value
    | each {|child| walk-flake ($path | append $child.name) $child.value }
    | flatten
  } else {
    [ (flake-leaf $path $value) ]
  }
}

export def normalize-flake-show []: record -> table {
  $in
  | transpose name value
  | each {|output| walk-flake [$output.name] $output.value }
  | flatten
}
