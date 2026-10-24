# Typed Nushell data can cross into the Nix evaluator without source rendering.

let select = (nix eval 'name: packages: packages.${name}')
let result = ($select | nix call "hello" {hello: 42, goodbye: 0})

print ($result | nix collect)

# NixValues stay lazy and can be embedded in newly constructed values.
let nested = ({answer: $result, values: [true null 1.5]} | into nix)
print ($nested | nix collect)

# Detailed realisation returns both the rendered value and physical store paths.
let generated = (nix eval '"${builtins.toFile "nu-nix-example" "hello"}"')
print ($generated | nix realise --details)
print ($generated | nix realise)

print (nix debug runtime status)
