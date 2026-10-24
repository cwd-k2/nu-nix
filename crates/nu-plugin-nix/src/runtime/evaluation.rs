//! Expression and virtual-lock flake evaluation.

use std::{
    ffi::{c_char, c_void},
    path::Path,
    ptr,
};

use nu_protocol::{LabeledError, Span, Value};

use crate::ffi;

use super::{
    Runtime,
    resources::{
        OwnedFlakeLockFlags, OwnedFlakeParseFlags, OwnedFlakeReference, OwnedLockedFlake,
        OwnedNixValue, c_string, copy_string,
    },
};

fn parse_attr_path(path: &str) -> Result<Vec<String>, String> {
    if path.is_empty() {
        return Ok(Vec::new());
    }
    let bytes = path.as_bytes();
    let mut offset = 0;
    let mut result = Vec::new();
    while offset < bytes.len() {
        let name = if bytes[offset] == b'"' {
            let start = offset;
            offset += 1;
            let mut escaped = false;
            while offset < bytes.len() {
                let byte = bytes[offset];
                offset += 1;
                if escaped {
                    escaped = false;
                } else if byte == b'\\' {
                    escaped = true;
                } else if byte == b'"' {
                    break;
                }
            }
            if bytes.get(offset.saturating_sub(1)) != Some(&b'"') {
                return Err("unterminated quoted attribute".into());
            }
            serde_json::from_str::<String>(&path[start..offset])
                .map_err(|error| format!("invalid quoted attribute: {error}"))?
        } else {
            let start = offset;
            while offset < bytes.len() && bytes[offset] != b'.' {
                if bytes[offset] == b'"' {
                    return Err("quotes must surround a complete attribute".into());
                }
                offset += 1;
            }
            let name = &path[start..offset];
            if name.is_empty() {
                return Err("attribute path contains an empty attribute".into());
            }
            name.to_owned()
        };
        result.push(name);
        if offset == bytes.len() {
            break;
        }
        if bytes[offset] != b'.' {
            return Err(
                "quoted attributes must be followed by a dot or the end of the path".into(),
            );
        }
        offset += 1;
        if offset == bytes.len() {
            return Err("attribute path contains an empty attribute".into());
        }
    }
    Ok(result)
}

impl Runtime {
    pub fn eval(
        &mut self,
        expression: &str,
        path: &Path,
        span: Span,
    ) -> Result<Value, LabeledError> {
        let expression = c_string(expression, "Nix expression")?;
        let path = path.to_str().ok_or_else(|| {
            LabeledError::new("evaluation path is not valid UTF-8")
                .with_label("choose a UTF-8 base path", span)
        })?;
        let path = c_string(path, "evaluation path")?;
        let value = OwnedNixValue::new(self.context.0, unsafe {
            ffi::nix_alloc_value(self.context.0, self.state.as_ptr())
        })
        .ok_or_else(|| LabeledError::new("failed to allocate a Nix value"))?;
        let result = unsafe {
            ffi::nix_expr_eval_from_string(
                self.context.0,
                self.state.as_ptr(),
                expression.as_ptr(),
                path.as_ptr(),
                value.as_ptr(),
            )
        };
        self.context
            .check(result)
            .map_err(|error| error.with_label("while evaluating this expression", span))?;
        self.insert(value, span)
    }

    pub fn flake_outputs(
        &mut self,
        reference: &str,
        base_path: &Path,
        span: Span,
    ) -> Result<Value, LabeledError> {
        let reference_c = c_string(reference, "flake reference")?;
        let base = base_path.to_str().ok_or_else(|| {
            LabeledError::new("flake base path is not valid UTF-8")
                .with_label("choose a UTF-8 base path", span)
        })?;
        let parse_flags = OwnedFlakeParseFlags::new(unsafe {
            ffi::nix_flake_reference_parse_flags_new(self.context.0, self.flake_settings.as_ptr())
        })
        .ok_or_else(|| {
            self.context
                .last_error_or("failed to allocate flake parse settings")
        })?;
        self.context.check(unsafe {
            ffi::nix_flake_reference_parse_flags_set_base_directory(
                self.context.0,
                parse_flags.as_ptr(),
                base.as_ptr().cast::<c_char>(),
                base.len(),
            )
        })?;

        let mut flake_reference: *mut ffi::nix_flake_reference = ptr::null_mut();
        let mut fragment = Vec::<u8>::new();
        let parse_result = unsafe {
            ffi::nix_flake_reference_and_fragment_from_string(
                self.context.0,
                self.fetch_settings.as_ptr(),
                self.flake_settings.as_ptr(),
                parse_flags.as_ptr(),
                reference_c.as_ptr(),
                reference.len(),
                &mut flake_reference,
                Some(copy_string),
                (&mut fragment as *mut Vec<u8>).cast::<c_void>(),
            )
        };
        if let Err(error) = self.context.check(parse_result) {
            return Err(error.with_label("while parsing this flake reference", span));
        }
        let flake_reference = OwnedFlakeReference::new(flake_reference)
            .ok_or_else(|| LabeledError::new("Nix returned an empty flake reference"))?;

        let lock_flags = OwnedFlakeLockFlags::new(unsafe {
            ffi::nix_flake_lock_flags_new(self.context.0, self.flake_settings.as_ptr())
        })
        .ok_or_else(|| {
            self.context
                .last_error_or("failed to allocate flake lock settings")
        })?;
        self.context.check(unsafe {
            if self.policy().locked {
                ffi::nix_flake_lock_flags_set_mode_check(self.context.0, lock_flags.as_ptr())
            } else {
                ffi::nix_flake_lock_flags_set_mode_virtual(self.context.0, lock_flags.as_ptr())
            }
        })?;

        let locked = OwnedLockedFlake::new(unsafe {
            ffi::nix_flake_lock(
                self.context.0,
                self.fetch_settings.as_ptr(),
                self.flake_settings.as_ptr(),
                self.state.as_ptr(),
                lock_flags.as_ptr(),
                flake_reference.as_ptr(),
            )
        });
        let Some(locked) = locked else {
            let code = unsafe { ffi::nix_err_code(self.context.0) };
            return match self.context.check(code) {
                Err(error) => Err(error.with_label("while resolving this flake reference", span)),
                Ok(()) => Err(LabeledError::new("failed to lock the flake")
                    .with_label("while resolving this flake reference", span)),
            };
        };

        let outputs = OwnedNixValue::new(self.context.0, unsafe {
            ffi::nix_locked_flake_get_output_attrs(
                self.context.0,
                self.flake_settings.as_ptr(),
                self.state.as_ptr(),
                locked.as_ptr(),
            )
        });
        let outputs = outputs.ok_or_else(|| {
            LabeledError::new("failed to evaluate flake outputs")
                .with_label("while evaluating this flake", span)
        })?;

        let fragment = match String::from_utf8(fragment) {
            Ok(fragment) => fragment,
            Err(_) => {
                return Err(LabeledError::new("flake fragment is not valid UTF-8")
                    .with_label("while parsing this flake reference", span));
            }
        };
        let mut selected = outputs;
        if !fragment.is_empty() {
            let attributes = parse_attr_path(&fragment).map_err(|error| {
                LabeledError::new(format!("invalid flake attribute path: {error}"))
                    .with_label("while selecting this flake output", span)
            })?;
            for name in attributes {
                self.force(selected.as_ptr())
                    .map_err(|error| error.with_label("while selecting this flake output", span))?;
                if unsafe { ffi::nix_get_type(self.context.0, selected.as_ptr()) }
                    != ffi::ValueType_NIX_TYPE_ATTRS
                {
                    return Err(LabeledError::new(format!(
                        "flake fragment `{fragment}` traverses a non-attribute value"
                    ))
                    .with_label("while selecting this flake output", span));
                }
                let name_c = c_string(&name, "flake fragment attribute")?;
                let exists = unsafe {
                    ffi::nix_has_attr_byname(
                        self.context.0,
                        selected.as_ptr(),
                        self.state.as_ptr(),
                        name_c.as_ptr(),
                    )
                };
                self.context
                    .check(unsafe { ffi::nix_err_code(self.context.0) })?;
                if !exists {
                    return Err(LabeledError::new(format!(
                        "flake output attribute `{name}` does not exist in fragment `{fragment}`"
                    ))
                    .with_label("while selecting this flake output", span));
                }
                let child = OwnedNixValue::new(self.context.0, unsafe {
                    ffi::nix_get_attr_byname_lazy(
                        self.context.0,
                        selected.as_ptr(),
                        self.state.as_ptr(),
                        name_c.as_ptr(),
                    )
                })
                .ok_or_else(|| {
                    self.context
                        .last_error_or("failed to access a flake output attribute")
                        .with_label("while selecting this flake output", span)
                })?;
                selected = child;
            }
        }
        self.insert(selected, span)
    }
}

#[cfg(test)]
mod tests {
    use super::parse_attr_path;

    #[test]
    fn parses_quoted_attributes() {
        assert_eq!(
            parse_attr_path(r#"packages."x86_64-linux"."name.with.dots""#).unwrap(),
            ["packages", "x86_64-linux", "name.with.dots"]
        );
        assert_eq!(
            parse_attr_path(r#""quoted\"name""#).unwrap(),
            ["quoted\"name"]
        );
    }

    #[test]
    fn rejects_malformed_paths() {
        for path in [
            ".leading",
            "trailing.",
            "two..dots",
            r#""unterminated"#,
            r#"a"b"#,
        ] {
            assert!(parse_attr_path(path).is_err(), "accepted {path:?}");
        }
    }
}
