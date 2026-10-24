//! Arena ownership and lazy traversal for plugin-visible Nix handles.

use std::ffi::{CStr, c_void};

use nu_protocol::{LabeledError, Span, Value};

use crate::{ffi, value::NixValue};

use super::{
    Runtime,
    resources::{OwnedNixValue, c_string},
};

impl Runtime {
    pub fn follow_attr(
        &mut self,
        handle: &NixValue,
        name: &str,
        span: Span,
        optional: bool,
        insensitive: bool,
    ) -> Result<Value, LabeledError> {
        let parent = self.pointer(handle)?;
        self.force(parent)?;
        if unsafe { ffi::nix_get_type(self.context.0, parent) } != ffi::ValueType_NIX_TYPE_ATTRS {
            return Err(LabeledError::new("Nix value is not an attribute set")
                .with_label(format!("cannot access attribute {name}"), span));
        }
        let resolved_name = if insensitive {
            match case_insensitive_attribute(&self.attribute_names(parent)?, name) {
                Some(name) => name,
                None if optional => return Ok(Value::nothing(span)),
                None => {
                    return Err(
                        LabeledError::new(format!("attribute `{name}` does not exist"))
                            .with_label("unknown Nix attribute", span),
                    );
                }
            }
        } else {
            name.to_owned()
        };
        let name_c = c_string(&resolved_name, "attribute name")?;
        let exists = unsafe {
            ffi::nix_has_attr_byname(self.context.0, parent, self.state.as_ptr(), name_c.as_ptr())
        };
        self.context
            .check(unsafe { ffi::nix_err_code(self.context.0) })?;
        if !exists {
            return if optional {
                Ok(Value::nothing(span))
            } else {
                Err(
                    LabeledError::new(format!("attribute `{resolved_name}` does not exist"))
                        .with_label("unknown Nix attribute", span),
                )
            };
        }
        let child = OwnedNixValue::new(self.context.0, unsafe {
            ffi::nix_get_attr_byname_lazy(
                self.context.0,
                parent,
                self.state.as_ptr(),
                name_c.as_ptr(),
            )
        })
        .ok_or_else(|| {
            self.context
                .last_error_or("failed to access a Nix attribute")
        })?;
        self.insert(child, span)
    }

    pub fn follow_index(
        &mut self,
        handle: &NixValue,
        index: usize,
        span: Span,
        optional: bool,
    ) -> Result<Value, LabeledError> {
        let parent = self.pointer(handle)?;
        self.force(parent)?;
        if unsafe { ffi::nix_get_type(self.context.0, parent) } != ffi::ValueType_NIX_TYPE_LIST {
            return Err(LabeledError::new("Nix value is not a list")
                .with_label(format!("cannot access index {index}"), span));
        }
        let length = unsafe { ffi::nix_get_list_size(self.context.0, parent) } as usize;
        if index >= length {
            return if optional {
                Ok(Value::nothing(span))
            } else {
                Err(LabeledError::new("Nix list index is out of bounds")
                    .with_label(format!("index {index}, length {length}"), span))
            };
        }
        let child = OwnedNixValue::new(self.context.0, unsafe {
            ffi::nix_get_list_byidx_lazy(self.context.0, parent, self.state.as_ptr(), index as u32)
        })
        .ok_or_else(|| {
            self.context
                .last_error_or("failed to access a Nix list element")
        })?;
        self.insert(child, span)
    }

    pub fn type_name(&mut self, handle: &NixValue) -> Result<String, LabeledError> {
        let pointer = self.pointer(handle)?;
        self.force(pointer)?;
        self.kind(pointer)
    }

    pub fn attr_names(&mut self, handle: &NixValue, span: Span) -> Result<Value, LabeledError> {
        let pointer = self.pointer(handle)?;
        self.force(pointer)?;
        if unsafe { ffi::nix_get_type(self.context.0, pointer) } != ffi::ValueType_NIX_TYPE_ATTRS {
            return Err(LabeledError::new("Nix value is not an attribute set")
                .with_label("cannot enumerate attributes", span));
        }
        let names = self.attribute_names(pointer)?;
        Ok(Value::list(
            names
                .into_iter()
                .map(|name| Value::string(name, span))
                .collect(),
            span,
        ))
    }

    pub fn release(&mut self, handle: &NixValue) -> Result<(), LabeledError> {
        self.validate_handle(handle)?;
        let pointer = self
            .values
            .remove(&handle.id)
            .ok_or_else(|| LabeledError::new("Nix value handle has already been released"))?;
        unsafe { ffi::nix_value_decref(self.context.0, pointer) };
        Ok(())
    }

    pub(super) fn insert(
        &mut self,
        value: OwnedNixValue,
        span: Span,
    ) -> Result<Value, LabeledError> {
        let id = self.next_id;
        self.next_id = self
            .next_id
            .checked_add(1)
            .ok_or_else(|| LabeledError::new("Nix value handle space has been exhausted"))?;
        self.values.insert(id, value.into_raw());
        Ok(NixValue {
            session: self.session,
            generation: self.generation,
            id,
        }
        .into_value(span))
    }

    pub(super) fn pointer(&self, value: &NixValue) -> Result<*mut ffi::nix_value, LabeledError> {
        self.validate_handle(value)?;
        self.values
            .get(&value.id)
            .copied()
            .ok_or_else(|| LabeledError::new("Nix value handle has expired"))
    }

    fn validate_handle(&self, value: &NixValue) -> Result<(), LabeledError> {
        value
            .validate_identity(self.session, self.generation)
            .map_err(Into::into)
    }

    pub(super) fn force(&self, value: *mut ffi::nix_value) -> Result<(), LabeledError> {
        let result = unsafe { ffi::nix_value_force(self.context.0, self.state.as_ptr(), value) };
        self.context.check(result)
    }

    pub(super) fn kind(&self, value: *mut ffi::nix_value) -> Result<String, LabeledError> {
        let name = unsafe { ffi::nix_get_typename(self.context.0, value) };
        if name.is_null() {
            return Err(LabeledError::new("failed to read a Nix value type"));
        }
        let result = unsafe { CStr::from_ptr(name) }
            .to_str()
            .map(str::to_owned)
            .map_err(|_| LabeledError::new("Nix value type is not valid UTF-8"));
        unsafe { libc::free(name.cast_mut().cast::<c_void>()) };
        result
    }

    pub(super) fn attribute_names(
        &self,
        value: *mut ffi::nix_value,
    ) -> Result<Vec<String>, LabeledError> {
        let length = unsafe { ffi::nix_get_attrs_size(self.context.0, value) };
        let mut names = Vec::with_capacity(length as usize);
        for index in 0..length {
            let name = unsafe {
                ffi::nix_get_attr_name_byidx(self.context.0, value, self.state.as_ptr(), index)
            };
            if name.is_null() {
                return Err(self
                    .context
                    .last_error_or("failed to read a Nix attribute name"));
            }
            names.push(
                unsafe { CStr::from_ptr(name) }
                    .to_str()
                    .map(str::to_owned)
                    .map_err(|_| LabeledError::new("Nix attribute name is not valid UTF-8"))?,
            );
        }
        names.sort();
        Ok(names)
    }
}

fn case_insensitive_attribute(names: &[String], requested: &str) -> Option<String> {
    let folded = requested.to_lowercase();
    names
        .iter()
        .rev()
        .find(|candidate| candidate.to_lowercase() == folded)
        .cloned()
}

#[cfg(test)]
mod tests {
    use super::case_insensitive_attribute;

    #[test]
    fn insensitive_traversal_is_missing_or_deterministic() {
        let names = vec!["Name".into(), "name".into(), "other".into()];
        assert_eq!(
            case_insensitive_attribute(&names, "NAME"),
            Some("name".into())
        );
        assert_eq!(case_insensitive_attribute(&names, "missing"), None);
    }
}
