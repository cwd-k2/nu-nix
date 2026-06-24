# nu-nix usage examples
#
# Prerequisites: autoLoad = true in your NixOS config (vendor autoload sources
# the module at startup automatically), or load manually:
#
#   use /run/current-system/sw/share/nushell/nu-nix *
#
# For development / without installing:
#   use /path/to/package/scripts/nu-nix/mod.nu *

# ── from nix ──────────────────────────────────────────────────────────────────

# Evaluate a Nix expression from a string
"{ x = 1 + 1; y = builtins.length [ 1 2 3 ]; }" | from nix
# => {x: 2, y: 3}

# Fetch a flake installable as a Nu value
from nix nixpkgs#hello.meta
# => {available: true, broken: false, description: "...", ...}

# Evaluate a .nix file
from nix --file ./myconfig.nix

# Pipe the result into Nu for further processing
from nix nixpkgs#hello.meta
  | select description license homepage
  | print


# ── to nix ────────────────────────────────────────────────────────────────────

# Serialize a Nu record to Nix attrset syntax
{
  enable: true
  port: 8080
  allowedHosts: ["localhost" "example.com"]
} | to nix
# =>
# {
#   enable = true;
#   port = 8080;
#   allowedHosts = [
#     "localhost"
#     "example.com"
#   ];
# }

# Keys with hyphens are valid Nix identifiers — output bare (no quotes)
{"max-connections": 100, "keep-alive": true} | to nix

# Nu tables become Nix lists of attrsets
[[name version]; ["hello" "2.12"] ["gcc" "13.2"]] | to nix

# Nu types with no Nix equivalent are converted automatically:
#   datetime  → ISO-8601 string
#   filesize  → bytes as int
#   duration  → nanoseconds as int
date now | to nix
1mib      | to nix    # => 1048576
500ms     | to nix    # => 500000000


# ── nu-nix commands ───────────────────────────────────────────────────────────
# These return Nu values (tables/records), fully composable in pipelines.

nu-nix search nixpkgs "python"
  | where version >= "3.11"
  | select pname version description

nu-nix build nixpkgs#hello
  | get path

nu-nix flake show .
  | where type == "packages" and system == "x86_64-linux"

nu-nix profile list
  | select name

# Pipeline composition: search results directly into to nix
nu-nix search nixpkgs "python" | first 5 | select pname version | to nix


# ── roundtrip ─────────────────────────────────────────────────────────────────

# from nix → to nix → from nix recovers the original value
let original = (from nix nixpkgs#git.meta)
let restored  = ($original | to nix | from nix)
print ($original == $restored)   # => true


# ── config generation ─────────────────────────────────────────────────────────

# Build a NixOS-style config from Nu data and write to a file
let users = [
  {name: "alice", groups: ["wheel" "docker"], shell: "nushell"}
  {name: "bob",   groups: ["audio"],          shell: "bash"}
]

$users
  | each {|u|
      {
        ($u.name): {
          isNormalUser: true
          extraGroups: $u.groups
          shell: $"pkgs.($u.shell)"
        }
      }
    }
  | into record
  | to nix
  | save users-generated.nix

# Inspect flake.lock inputs as a Nu table
^nix flake metadata --json
  | from json
  | get locks.nodes
  | transpose name info
  | where info.locked? != null
  | each {|r| {name: $r.name, rev: $r.info.locked.rev?, type: $r.info.locked.type?}}
  | sort-by name
