use std::{env, path::PathBuf};

fn main() {
    for library in [
        "nix-util-c",
        "nix-store-c",
        "nix-expr-c",
        "nix-fetchers-c",
        "nix-flake-c",
    ] {
        pkg_config::Config::new()
            .probe(library)
            .unwrap_or_else(|error| panic!("failed to locate {library}: {error}"));
    }

    println!("cargo:rerun-if-changed=wrapper.h");
    let bindings = bindgen::Builder::default()
        .header("wrapper.h")
        .allowlist_function("nix_.*")
        .allowlist_type("nix_.*")
        .allowlist_type("EvalState")
        .allowlist_type("Store")
        .allowlist_type("ValueType")
        .allowlist_var("NIX_.*")
        .derive_default(true)
        .generate()
        .expect("failed to generate Nix C API bindings");

    let output = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR is set by Cargo"));
    bindings
        .write_to_file(output.join("nix_api.rs"))
        .expect("failed to write Nix C API bindings");
}
