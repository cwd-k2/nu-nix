use ./support/assert.nu
use ../package/scripts/nu-nix/normalize.nu *

let builds = ([{
  drvPath: "/nix/store/example.drv"
  outputs: {out: "/nix/store/example", dev: "/nix/store/example-dev"}
}] | normalize-build)
assert equal ($builds | length) 2
assert equal ($builds | where output == out | get path.0) "/nix/store/example"
assert equal ($builds | get drvPath | uniq) ["/nix/store/example.drv"]

let searches = ({
  "legacyPackages.x86_64-linux.hello": {
    pname: "hello"
    version: "2.12"
    description: "A greeting"
    license: "GPL-3.0-or-later"
  }
} | normalize-search)
assert equal $searches.0.attr "legacyPackages.x86_64-linux.hello"
assert equal $searches.0.license "GPL-3.0-or-later"

let paths = ({
  "/nix/store/example": {narSize: 123, references: ["/nix/store/ref"]}
} | normalize-path-info)
assert equal $paths.0.path "/nix/store/example"
assert equal $paths.0.narSize 123

let environment = ({variables: {
  PATH: {type: "array", value: ["/bin"]}
  EDITOR: {type: "var", value: "nvim"}
}} | normalize-dev-environment)
assert equal ($environment | where name == EDITOR | get value.0) "nvim"

let activation = ({
  variables: {
    PATH: {type: "exported", value: $"/nix/store/one/bin(char esep)/nix/store/two/bin"}
    EDITOR: {type: "exported", value: "nvim"}
    HOME: {type: "exported", value: "/homeless-shelter"}
    shellHook: {type: "var", value: "echo ignored"}
  }
} | normalize-dev-activation)
assert equal $activation.updates.PATH ["/nix/store/one/bin" "/nix/store/two/bin"]
assert equal $activation.updates.EDITOR "nvim"
assert ("HOME" not-in ($activation.updates | columns))
assert ("HOME" in $activation.skipped)
assert ("shellHook" in $activation.skipped)

let profile = ({elements: {
  hello: {storePaths: ["/nix/store/hello"], active: true}
}} | normalize-profile)
assert equal $profile.0.name "hello"
assert equal $profile.0.active true

let outputs = ({
  packages: {
    "x86_64-linux": {
      scope: {
        hello: {type: "derivation", description: "A greeting"}
      }
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

let hello = ($outputs | where path == "packages.x86_64-linux.scope.hello" | first)
assert equal $hello.system "x86_64-linux"
assert equal $hello.name "scope.hello"
assert equal $hello.kind "derivation"
assert equal $hello.description "A greeting"

let formatter = ($outputs | where path == "formatter.x86_64-linux" | first)
assert equal $formatter.system "x86_64-linux"
assert equal $formatter.name null

let module = ($outputs | where path == "homeManagerModules" | first)
assert equal $module.name null
assert equal $module.kind "unknown"

let false_positive = ($outputs | where path == "linux-tools.helper" | first)
assert equal $false_positive.system null
assert equal $false_positive.name "helper"

print "structured command normalizers passed"
