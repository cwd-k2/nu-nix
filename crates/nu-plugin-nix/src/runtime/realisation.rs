//! Contextual Nix string realisation and physical store-path reporting.

use std::ffi::c_void;

use nu_protocol::{LabeledError, Record, Span, Value};

use crate::{ffi, value::NixValue};

use super::{
    Runtime,
    resources::{OwnedRealisedString, copy_string},
};

struct RealisedPath {
    hash: String,
    name: String,
    physical: Option<String>,
}

impl Runtime {
    pub fn realise_string(
        &mut self,
        handle: &NixValue,
        span: Span,
        details: bool,
    ) -> Result<Value, LabeledError> {
        let (value, paths) = self.realise_string_details(handle, span)?;
        if !details {
            return Ok(Value::string(value, span));
        }
        let mut record = Record::with_capacity(3);
        record.push("value", Value::string(value, span));
        record.push(
            "storePaths",
            Value::list(
                paths
                    .iter()
                    .map(|path| {
                        let mut item = Record::with_capacity(2);
                        item.push("hash", Value::string(&path.hash, span));
                        item.push("name", Value::string(&path.name, span));
                        Value::record(item, span)
                    })
                    .collect(),
                span,
            ),
        );
        record.push(
            "physicalPaths",
            Value::list(
                paths
                    .into_iter()
                    .filter_map(|path| path.physical.map(|value| Value::string(value, span)))
                    .collect(),
                span,
            ),
        );
        Ok(Value::record(record, span))
    }

    fn realise_string_details(
        &mut self,
        handle: &NixValue,
        span: Span,
    ) -> Result<(String, Vec<RealisedPath>), LabeledError> {
        let pointer = self.pointer(handle)?;
        self.force(pointer)?;
        if unsafe { ffi::nix_get_type(self.context.0, pointer) } != ffi::ValueType_NIX_TYPE_STRING {
            return Err(LabeledError::new("Nix value is not a string")
                .with_label("only contextual Nix strings can be realised", span));
        }
        let realised = OwnedRealisedString::new(unsafe {
            ffi::nix_string_realise(self.context.0, self.state.as_ptr(), pointer, false)
        });
        let Some(realised) = realised else {
            let code = unsafe { ffi::nix_err_code(self.context.0) };
            return match self.context.check(code) {
                Err(error) => Err(error.with_label("while realising this Nix string", span)),
                Ok(()) => Err(LabeledError::new("failed to realise a Nix string")),
            };
        };
        let start = unsafe { ffi::nix_realised_string_get_buffer_start(realised.as_ptr()) };
        let length = unsafe { ffi::nix_realised_string_get_buffer_size(realised.as_ptr()) };
        if start.is_null() {
            Err(LabeledError::new(
                "Nix returned an empty realised string buffer",
            ))
        } else {
            let bytes = unsafe { std::slice::from_raw_parts(start.cast::<u8>(), length) };
            let value = String::from_utf8(bytes.to_vec()).map_err(|_| {
                LabeledError::new("realised Nix string is not valid UTF-8")
                    .with_label("cannot represent this value as a Nushell string", span)
            })?;
            let count = unsafe { ffi::nix_realised_string_get_store_path_count(realised.as_ptr()) };
            let mut paths = Vec::with_capacity(count);
            for index in 0..count {
                let store_path =
                    unsafe { ffi::nix_realised_string_get_store_path(realised.as_ptr(), index) };
                if store_path.is_null() {
                    return Err(LabeledError::new(
                        "Nix returned an empty realised store path",
                    ));
                }
                let mut physical = Vec::<u8>::new();
                let code = unsafe {
                    ffi::nix_store_real_path(
                        self.context.0,
                        self.store.as_ptr(),
                        store_path.cast_mut(),
                        Some(copy_string),
                        (&mut physical as *mut Vec<u8>).cast::<c_void>(),
                    )
                };
                let physical = if self.context.check(code).is_ok() {
                    Some(String::from_utf8(physical).map_err(|_| {
                        LabeledError::new("realised store path is not valid UTF-8")
                            .with_label("cannot represent this path in Nushell", span)
                    })?)
                } else {
                    None
                };
                let mut name = Vec::<u8>::new();
                unsafe {
                    ffi::nix_store_path_name(
                        store_path,
                        Some(copy_string),
                        (&mut name as *mut Vec<u8>).cast::<c_void>(),
                    )
                };
                let name = String::from_utf8(name)
                    .map_err(|_| LabeledError::new("Nix store path name is not valid UTF-8"))?;
                let mut hash = ffi::nix_store_path_hash_part { bytes: [0; 20] };
                self.context.check(unsafe {
                    ffi::nix_store_path_hash(self.context.0, store_path, &mut hash)
                })?;
                let hash = hash
                    .bytes
                    .iter()
                    .map(|byte| format!("{byte:02x}"))
                    .collect();
                paths.push(RealisedPath {
                    hash,
                    name,
                    physical,
                });
            }
            paths
                .sort_by(|left, right| left.hash.cmp(&right.hash).then(left.name.cmp(&right.name)));
            Ok((value, paths))
        }
    }
}
