use ./support/assert.nu
use ../../nushell/nu-nix/normalize.nu *
use ../../nushell/nu-nix/completions.nu format-flake-completions

let builds = ([{
  drvPath: "/nix/store/example.drv"
  outputs: {out: "/nix/store/example", dev: "/nix/store/example-dev"}
}] | normalize-build)
assert equal $builds [
  {output: "out", path: "/nix/store/example", drvPath: "/nix/store/example.drv"}
  {output: "dev", path: "/nix/store/example-dev", drvPath: "/nix/store/example.drv"}
]

let searches = ({
  "legacyPackages.x86_64-linux.hello": {
    pname: "hello"
    version: "2.12"
    description: "A greeting"
    license: "GPL-3.0-or-later"
  }
} | normalize-search)
assert equal $searches [{
  pname: "hello"
  version: "2.12"
  description: "A greeting"
  license: "GPL-3.0-or-later"
  attr: "legacyPackages.x86_64-linux.hello"
}]

let paths = ({
  "/nix/store/example": {narSize: 123, references: ["/nix/store/ref"]}
  "/nix/store/missing": {}
} | normalize-path-info)
assert equal $paths [{
  narSize: 123
  references: ["/nix/store/ref"]
  path: "/nix/store/example"
}]

let environment = ({variables: {
  PATH: {type: "array", value: ["/bin"]}
  EDITOR: {type: "var", value: "nvim"}
}} | normalize-dev-environment)
assert equal $environment [
  {type: "array", value: ["/bin"], name: "PATH"}
  {type: "var", value: "nvim", name: "EDITOR"}
]

let activation = ({
  variables: {
    PATH: {type: "exported", value: $"/nix/store/one/bin(char esep)/nix/store/two/bin"}
    EDITOR: {type: "exported", value: "nvim"}
    HOME: {type: "exported", value: "/homeless-shelter"}
    shellHook: {type: "var", value: "echo ignored"}
  }
} | normalize-dev-activation)
assert equal $activation {
  updates: {
    PATH: ["/nix/store/one/bin" "/nix/store/two/bin"]
    EDITOR: "nvim"
  }
  skipped: ["HOME" "shellHook"]
}

let profile = ({elements: {
  hello: {storePaths: ["/nix/store/hello"], active: true}
}} | normalize-profile)
assert equal $profile [{
  storePaths: ["/nix/store/hello"]
  active: true
  name: "hello"
}]

let profile_diff = (normalize-profile-diff {
  elements: {
    hello: {storePaths: ["/nix/store/hello-1"], version: "1"}
    removed: {storePaths: ["/nix/store/removed"]}
    stable: {storePaths: ["/nix/store/stable"]}
  }
} {
  elements: {
    hello: {storePaths: ["/nix/store/hello-2"], version: "2"}
    added: {storePaths: ["/nix/store/added"]}
    stable: {storePaths: ["/nix/store/stable"]}
  }
})
assert equal ($profile_diff | get name) [added hello removed]
assert equal ($profile_diff | where name == hello | get change.0) "updated"
assert equal ($profile_diff | where name == removed | get toStorePaths.0) []

let profile_diff_all = (normalize-profile-diff --all {
  elements: {stable: {storePaths: ["/nix/store/stable"]}}
} {
  elements: {stable: {storePaths: ["/nix/store/stable"]}}
})
assert equal $profile_diff_all.0.change "unchanged"

let closure_diff = (normalize-closure-diff {
  "/nix/store/old": {narSize: 100, closureSize: 300}
  "/nix/store/shared": {narSize: 50, closureSize: 50}
} {
  "/nix/store/new": {narSize: 120, closureSize: 360}
  "/nix/store/shared": {narSize: 50, closureSize: 50}
})
assert equal ($closure_diff | get path) ["/nix/store/new" "/nix/store/old"]
assert equal ($closure_diff | where path == "/nix/store/new" | get narSizeDelta.0) 120
assert equal ($closure_diff | where path == "/nix/store/old" | get narSizeDelta.0) (-100)

let outputs = ({
  packages: {
    "x86_64-linux": {
      type: {type: "derivation", description: "A package named type"}
      "x86_64-linux": {type: "derivation", description: "A package named like a system"}
      scope: {
        hello: {type: "derivation", description: "A greeting"}
      }
      omitted: {}
    }
  }
  formatter: {
    "x86_64-linux": {type: "derivation", description: "Formatter"}
  }
  homeManagerModules: {type: "unknown"}
  "linux-tools": {
    helper: {type: "unknown"}
  }
} | normalize-flake-show)

assert equal ($outputs | get path) [
  "packages.x86_64-linux.type"
  "packages.x86_64-linux.x86_64-linux"
  "packages.x86_64-linux.scope.hello"
  "formatter.x86_64-linux"
  "homeManagerModules"
  "linux-tools.helper"
]

let hello = ($outputs | where path == "packages.x86_64-linux.scope.hello" | first)
assert equal $hello.system "x86_64-linux"
assert equal $hello.name "scope.hello"
assert equal $hello.kind "derivation"
assert equal $hello.description "A greeting"

let type_package = ($outputs | where path == "packages.x86_64-linux.type" | first)
assert equal $type_package.name "type"
assert equal $type_package.kind "derivation"

let system_package = ($outputs | where path == "packages.x86_64-linux.x86_64-linux" | first)
assert equal $system_package.system "x86_64-linux"
assert equal $system_package.name "x86_64-linux"

let formatter = ($outputs | where path == "formatter.x86_64-linux" | first)
assert equal $formatter.system "x86_64-linux"
assert equal $formatter.name null

let module = ($outputs | where path == "homeManagerModules" | first)
assert equal $module.name null
assert equal $module.kind "unknown"

let false_positive = ($outputs | where path == "linux-tools.helper" | first)
assert equal $false_positive.system null
assert equal $false_positive.name "helper"

let completions = (format-flake-completions ".#sc" $outputs [packages])
assert equal $completions [{
  value: ".#scope.hello"
  description: "derivation · x86_64-linux · A greeting"
}]

print "structured command normalizers passed"
