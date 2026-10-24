//! Bounded, typed conversion between Nushell data and native Nix values.

use std::ffi::{CStr, c_void};

use nu_protocol::{LabeledError, Record, Span, Value};

use crate::{ffi, value::NixValue};

use super::{
    Runtime,
    limits::{LimitExceeded, TraversalBudget},
    resources::{OwnedBindingsBuilder, OwnedListBuilder, OwnedNixValue, c_string, copy_string},
};

const MAX_COLLECT_DEPTH: usize = 256;
const MAX_COLLECT_NODES: usize = 100_000;
const MAX_CONVERT_DEPTH: usize = 256;
const MAX_CONVERT_NODES: usize = 100_000;

impl Runtime {
    pub fn convert_to_nu(&mut self, handle: &NixValue, span: Span) -> Result<Value, LabeledError> {
        let pointer = self.pointer(handle)?;
        let mut budget = TraversalBudget::new(MAX_COLLECT_DEPTH, MAX_COLLECT_NODES);
        self.convert(pointer, span, 0, &mut budget)
    }

    pub fn convert_from_nu_value(
        &mut self,
        value: &Value,
        span: Span,
        as_path: bool,
    ) -> Result<Value, LabeledError> {
        if as_path && !matches!(value, Value::String { .. }) {
            return Err(LabeledError::new("`into nix --path` requires a string")
                .with_label(format!("got {}", value.get_type()), value.span()));
        }
        let mut budget = TraversalBudget::new(MAX_CONVERT_DEPTH, MAX_CONVERT_NODES);
        let converted = self.convert_from_nu(value, 0, &mut budget, as_path)?;
        self.insert(converted, span)
    }

    pub fn call(
        &mut self,
        function: &NixValue,
        arguments: &[Value],
        span: Span,
    ) -> Result<Value, LabeledError> {
        if arguments.is_empty() {
            return Err(LabeledError::new("nix call requires at least one argument")
                .with_label("provide an argument after the command", span));
        }
        let function = self.pointer(function)?;
        let mut budget = TraversalBudget::new(MAX_CONVERT_DEPTH, MAX_CONVERT_NODES);
        let owned = arguments
            .iter()
            .map(|argument| self.convert_from_nu(argument, 0, &mut budget, false))
            .collect::<Result<Vec<_>, _>>()?;
        let mut pointers = owned.iter().map(OwnedNixValue::as_ptr).collect::<Vec<_>>();
        let result = OwnedNixValue::new(self.context.0, unsafe {
            ffi::nix_alloc_value(self.context.0, self.state.as_ptr())
        })
        .ok_or_else(|| LabeledError::new("failed to allocate a Nix call result"))?;
        let code = unsafe {
            ffi::nix_value_call_multi(
                self.context.0,
                self.state.as_ptr(),
                function,
                pointers.len(),
                pointers.as_mut_ptr(),
                result.as_ptr(),
            )
        };
        self.context
            .check(code)
            .map_err(|error| error.with_label("while calling this Nix function", span))?;
        self.insert(result, span)
    }

    fn convert_from_nu(
        &mut self,
        value: &Value,
        depth: usize,
        budget: &mut TraversalBudget,
        as_path: bool,
    ) -> Result<OwnedNixValue, LabeledError> {
        budget
            .enter(depth)
            .map_err(|error| conversion_limit_error(error, value.span()))?;

        if let Value::Custom { val, .. } = value
            && let Some(handle) = val.as_any().downcast_ref::<NixValue>()
        {
            let source = self.pointer(handle)?;
            let target = self.allocate_value()?;
            self.context
                .check(unsafe { ffi::nix_copy_value(self.context.0, target.as_ptr(), source) })?;
            return Ok(target);
        }

        let target = self.allocate_value()?;
        let code = match value {
            Value::Nothing { .. } => unsafe { ffi::nix_init_null(self.context.0, target.as_ptr()) },
            Value::Bool { val, .. } => unsafe {
                ffi::nix_init_bool(self.context.0, target.as_ptr(), *val)
            },
            Value::Int { val, .. } => unsafe {
                ffi::nix_init_int(self.context.0, target.as_ptr(), *val)
            },
            Value::Float { val, .. } if val.is_finite() => unsafe {
                ffi::nix_init_float(self.context.0, target.as_ptr(), *val)
            },
            Value::Float { .. } => {
                return Err(LabeledError::new("Nix cannot represent a non-finite float")
                    .with_label("unsupported float", value.span()));
            }
            Value::String { val, .. } => {
                let string = c_string(val, if as_path { "Nix path" } else { "Nix string" })?;
                if as_path {
                    unsafe {
                        ffi::nix_init_path_string(
                            self.context.0,
                            self.state.as_ptr(),
                            target.as_ptr(),
                            string.as_ptr(),
                        )
                    }
                } else {
                    unsafe {
                        ffi::nix_init_string(self.context.0, target.as_ptr(), string.as_ptr())
                    }
                }
            }
            Value::List { vals, .. } if !as_path => {
                return self.convert_list(vals, target, depth, budget);
            }
            Value::Record { val, .. } if !as_path => {
                return self.convert_record(val, target, depth, budget);
            }
            _ => {
                return Err(LabeledError::new(format!(
                    "cannot convert Nushell {} to a Nix value",
                    value.get_type()
                ))
                .with_label(
                    "supported types are null, bool, int, float, string, list, and record",
                    value.span(),
                ));
            }
        };
        self.context.check(code)?;
        Ok(target)
    }

    fn allocate_value(&self) -> Result<OwnedNixValue, LabeledError> {
        OwnedNixValue::new(self.context.0, unsafe {
            ffi::nix_alloc_value(self.context.0, self.state.as_ptr())
        })
        .ok_or_else(|| self.context.last_error_or("failed to allocate a Nix value"))
    }

    fn convert_list(
        &mut self,
        values: &[Value],
        target: OwnedNixValue,
        depth: usize,
        budget: &mut TraversalBudget,
    ) -> Result<OwnedNixValue, LabeledError> {
        if budget.ensure_children(values.len()).is_err() || values.len() > u32::MAX as usize {
            return Err(LabeledError::new(
                "Nushell list is too large to convert to Nix",
            ));
        }
        let mut children = Vec::with_capacity(values.len());
        let builder = OwnedListBuilder::new(unsafe {
            ffi::nix_make_list_builder(self.context.0, self.state.as_ptr(), values.len())
        })
        .ok_or_else(|| {
            self.context
                .last_error_or("failed to allocate a Nix list builder")
        })?;
        for value in values {
            children.push(self.convert_from_nu(value, depth + 1, budget, false)?);
        }
        for (index, child) in children.iter().enumerate() {
            self.context.check(unsafe {
                ffi::nix_list_builder_insert(
                    self.context.0,
                    builder.as_ptr(),
                    index as u32,
                    child.as_ptr(),
                )
            })?;
        }
        self.context.check(unsafe {
            ffi::nix_make_list(self.context.0, builder.as_ptr(), target.as_ptr())
        })?;
        Ok(target)
    }

    fn convert_record(
        &mut self,
        record: &Record,
        target: OwnedNixValue,
        depth: usize,
        budget: &mut TraversalBudget,
    ) -> Result<OwnedNixValue, LabeledError> {
        if budget.ensure_children(record.len()).is_err() {
            return Err(LabeledError::new(
                "Nushell record is too large to convert to Nix",
            ));
        }
        let mut children = Vec::with_capacity(record.len());
        let builder = OwnedBindingsBuilder::new(unsafe {
            ffi::nix_make_bindings_builder(self.context.0, self.state.as_ptr(), record.len())
        })
        .ok_or_else(|| {
            self.context
                .last_error_or("failed to allocate Nix bindings")
        })?;
        for (name, value) in record.iter() {
            let name = c_string(name, "record key")?;
            let child = self.convert_from_nu(value, depth + 1, budget, false)?;
            self.context.check(unsafe {
                ffi::nix_bindings_builder_insert(
                    self.context.0,
                    builder.as_ptr(),
                    name.as_ptr(),
                    child.as_ptr(),
                )
            })?;
            children.push(child);
        }
        self.context.check(unsafe {
            ffi::nix_make_attrs(self.context.0, target.as_ptr(), builder.as_ptr())
        })?;
        Ok(target)
    }

    fn convert(
        &mut self,
        value: *mut ffi::nix_value,
        span: Span,
        depth: usize,
        budget: &mut TraversalBudget,
    ) -> Result<Value, LabeledError> {
        budget
            .enter(depth)
            .map_err(|error| collection_limit_error(error, span))?;
        self.force(value)?;
        let value_type = unsafe { ffi::nix_get_type(self.context.0, value) };
        match value_type {
            ffi::ValueType_NIX_TYPE_NULL => Ok(Value::nothing(span)),
            ffi::ValueType_NIX_TYPE_BOOL => Ok(Value::bool(
                unsafe { ffi::nix_get_bool(self.context.0, value) },
                span,
            )),
            ffi::ValueType_NIX_TYPE_INT => Ok(Value::int(
                unsafe { ffi::nix_get_int(self.context.0, value) },
                span,
            )),
            ffi::ValueType_NIX_TYPE_FLOAT => Ok(Value::float(
                unsafe { ffi::nix_get_float(self.context.0, value) },
                span,
            )),
            ffi::ValueType_NIX_TYPE_STRING => {
                let mut bytes = Vec::<u8>::new();
                let result = unsafe {
                    ffi::nix_get_string(
                        self.context.0,
                        value,
                        Some(copy_string),
                        (&mut bytes as *mut Vec<u8>).cast::<c_void>(),
                    )
                };
                self.context.check(result)?;
                let value = String::from_utf8(bytes).map_err(|_| {
                    LabeledError::new("Nix string is not valid UTF-8")
                        .with_label("cannot represent this value as a Nushell string", span)
                })?;
                Ok(Value::string(value, span))
            }
            ffi::ValueType_NIX_TYPE_PATH => {
                let path = unsafe { ffi::nix_get_path_string(self.context.0, value) };
                if path.is_null() {
                    Err(LabeledError::new("failed to read a Nix path"))
                } else {
                    let path = unsafe { CStr::from_ptr(path) }.to_str().map_err(|_| {
                        LabeledError::new("Nix path is not valid UTF-8")
                            .with_label("cannot represent this path in Nushell", span)
                    })?;
                    Ok(Value::string(path, span))
                }
            }
            ffi::ValueType_NIX_TYPE_LIST => {
                let length = unsafe { ffi::nix_get_list_size(self.context.0, value) };
                budget
                    .ensure_children(length as usize)
                    .map_err(|error| collection_limit_error(error, span))?;
                let mut values = Vec::with_capacity(length as usize);
                for index in 0..length {
                    let child = OwnedNixValue::new(self.context.0, unsafe {
                        ffi::nix_get_list_byidx_lazy(
                            self.context.0,
                            value,
                            self.state.as_ptr(),
                            index,
                        )
                    })
                    .ok_or_else(|| {
                        self.context
                            .last_error_or("failed to read a Nix list element")
                    })?;
                    values.push(self.convert(child.as_ptr(), span, depth + 1, budget)?);
                }
                Ok(Value::list(values, span))
            }
            ffi::ValueType_NIX_TYPE_ATTRS => {
                let length = unsafe { ffi::nix_get_attrs_size(self.context.0, value) } as usize;
                budget
                    .ensure_children(length)
                    .map_err(|error| collection_limit_error(error, span))?;
                let names = self.attribute_names(value)?;
                let mut record = Record::with_capacity(names.len());
                for name in names {
                    let name_c = c_string(&name, "attribute name")?;
                    let child = OwnedNixValue::new(self.context.0, unsafe {
                        ffi::nix_get_attr_byname_lazy(
                            self.context.0,
                            value,
                            self.state.as_ptr(),
                            name_c.as_ptr(),
                        )
                    })
                    .ok_or_else(|| self.context.last_error_or("failed to read a Nix attribute"))?;
                    record.push(name, self.convert(child.as_ptr(), span, depth + 1, budget)?);
                }
                Ok(Value::record(record, span))
            }
            _ => Err(LabeledError::new(format!(
                "cannot convert Nix {} to a Nushell value",
                self.kind(value)?
            ))
            .with_label("keep it as NixValue or use a native operation", span)),
        }
    }
}

fn conversion_limit_error(error: LimitExceeded, span: Span) -> LabeledError {
    match error {
        LimitExceeded::Depth => LabeledError::new(format!(
            "Nushell value exceeds the conversion depth limit of {MAX_CONVERT_DEPTH}"
        ))
        .with_label("convert a shallower value", span),
        LimitExceeded::Nodes => LabeledError::new(format!(
            "Nushell value exceeds the conversion limit of {MAX_CONVERT_NODES} nodes"
        ))
        .with_label("convert a smaller value", span),
    }
}

fn collection_limit_error(error: LimitExceeded, span: Span) -> LabeledError {
    match error {
        LimitExceeded::Depth => LabeledError::new(format!(
            "Nix value exceeds the collection depth limit of {MAX_COLLECT_DEPTH}"
        ))
        .with_label(
            "collection stopped before exhausting the plugin stack",
            span,
        ),
        LimitExceeded::Nodes => LabeledError::new(format!(
            "Nix value exceeds the collection limit of {MAX_COLLECT_NODES} nodes"
        ))
        .with_label("collect a smaller subtree", span),
    }
}
