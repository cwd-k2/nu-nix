# `to nix` — serialize a Nu value to Nix expression syntax.
#
# Type mapping:
#
#   Nu type     Nix syntax          Notes
#   ─────────── ─────────────────── ─────────────────────────────────────────
#   null        null
#   bool        true / false
#   int         42                  any 64-bit signed integer
#   float       3.14                appends .0 when Nu serialises as "1" not "1.0"
#   string      "..."               \  "  \n  \r  \t  ${  all escaped
#   datetime    "2024-01-15T..."    ISO-8601; Nix has no date type
#   filesize    1024                raw byte count as int; Nix has no filesize type
#   duration    1000000000          nanoseconds as int; Nix has no duration type
#   list        [ ... ]             items indented 2 spaces per nesting level
#   table       [ { ... } ... ]     treated as a list of attrsets
#   record      { key = value; }    keys quoted only when not valid Nix identifiers
#   binary      (error)             use `encode base64 | to nix`
#                                   or convert to a byte list first


# ── Internal helpers ──────────────────────────────────────────────────────────

# Return a string of n*2 spaces (indentation helper).
def ind [n: int]: nothing -> string {
  0..<$n | each { "  " } | str join ""
}

# Wrap a string in Nix double-quote syntax, escaping all special characters.
def nix-string []: string -> string {
  let body = ($in
    | str replace --all "\\" "\\\\"   # must come first to avoid double-escaping
    | str replace --all "\"" "\\\""
    | str replace --all "\n" "\\n"
    | str replace --all "\r" "\\r"
    | str replace --all "\t" "\\t"
    | str replace --all "${" "\\${")  # prevent Nix antiquotation
  $"\"($body)\""
}

# Return the key as a bare Nix identifier if valid, otherwise as a quoted string.
# Valid Nix identifiers: [a-zA-Z_] followed by [a-zA-Z0-9_'−]*.
# The hyphen must appear first in the character class to avoid a regex range.
def nix-key [k: string]: nothing -> string {
  if ($k =~ "^[a-zA-Z_][-a-zA-Z0-9_']*$") { $k } else { $k | nix-string }
}

# Recursively convert a Nu value to a Nix expression string.
def to-nix-inner [depth: int]: any -> string {
  let val = $in
  let t   = ($val | describe)
  let i   = ind $depth
  let i1  = ind ($depth + 1)

  if $val == null {
    "null"
  } else if $t == "bool" {
    if $val { "true" } else { "false" }
  } else if $t == "int" {
    $val | into string
  } else if $t == "float" {
    let s = ($val | into string)
    # Nushell may drop the decimal point for whole floats (e.g. 1.0 → "1").
    # Append ".0" so Nix treats the value as a float, not an int.
    if ($s | str contains ".") or ($s | str contains "e") { $s } else { $"($s).0" }
  } else if $t == "string" {
    $val | nix-string
  } else if $t == "datetime" {
    $val | format date "%Y-%m-%dT%H:%M:%S%z" | nix-string
  } else if $t == "filesize" {
    $val | into int | into string
  } else if $t == "duration" {
    $val | into int | into string
  } else if ($t | str starts-with "list") or ($t | str starts-with "table") {
    if ($val | is-empty) {
      "[ ]"
    } else {
      let items = ($val | each {|it| $"($i1)($it | to-nix-inner ($depth + 1))" })
      $"[\n($items | str join "\n")\n($i)]"
    }
  } else if ($t | str starts-with "record") {
    let pairs = ($val | transpose k v)
    if ($pairs | is-empty) {
      "{ }"
    } else {
      let lines = ($pairs | each {|it|
        $"($i1)(nix-key $it.k) = ($it.v | to-nix-inner ($depth + 1));"
      })
      $"{\n($lines | str join "\n")\n($i)}"
    }
  } else if $t == "binary" {
    error make {
      msg: "binary values have no Nix equivalent"
      help: "as base64 string:  encode base64 | to nix\nas byte list:      encode hex | split chars | chunks 2 | each { str join | into int --radix 16 } | to nix"
    }
  } else {
    error make { msg: $"cannot convert ($t) to Nix" }
  }
}


# ── Public command ────────────────────────────────────────────────────────────

# Serialize a Nu value to Nix expression syntax.
export def "to nix" []: any -> string {
  $in | to-nix-inner 0
}
