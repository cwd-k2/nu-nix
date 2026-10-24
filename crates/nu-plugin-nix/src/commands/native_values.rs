use std::path::PathBuf;

use nu_plugin::{EngineInterface, EvaluatedCall, SimplePluginCommand};
use nu_protocol::{Category, LabeledError, Signature, SyntaxShape, Type, Value};

use super::canonical_path;
use crate::{plugin::NixPlugin, value::NixValue};

pub(crate) struct IntoNix;

impl SimplePluginCommand for IntoNix {
    type Plugin = NixPlugin;

    fn name(&self) -> &str {
        "into nix"
    }

    fn description(&self) -> &str {
        "Convert typed Nushell data directly into a native Nix value."
    }

    fn signature(&self) -> Signature {
        Signature::build(SimplePluginCommand::name(self))
            .switch(
                "path",
                "convert a top-level string to a Nix path instead of a string",
                None,
            )
            .input_output_type(Type::Any, Type::Custom("NixValue".into()))
            .category(Category::Conversions)
    }

    fn run(
        &self,
        plugin: &NixPlugin,
        engine: &EngineInterface,
        call: &EvaluatedCall,
        input: &Value,
    ) -> Result<Value, LabeledError> {
        let as_path = call.has_flag("path")?;
        let resolved;
        let input = if as_path {
            let path = PathBuf::from(input.as_str().map_err(LabeledError::from)?);
            let path = canonical_path(path, engine, input.span(), "Nix path", "path must exist")?;
            let path = path.into_os_string().into_string().map_err(|_| {
                LabeledError::new("Nix path is not valid UTF-8")
                    .with_label("choose a UTF-8 path", input.span())
            })?;
            resolved = Value::string(path, input.span());
            &resolved
        } else {
            input
        };
        let input = input.clone();
        let span = call.head;
        if let Value::Custom { val, .. } = &input
            && let Some(handle) = val.as_any().downcast_ref::<NixValue>()
        {
            let handle = handle.clone();
            plugin.with_handle_runtime(handle, move |runtime, _handle| {
                runtime.convert_from_nu_value(&input, span, as_path)
            })
        } else {
            plugin.with_runtime(move |runtime| runtime.convert_from_nu_value(&input, span, as_path))
        }
    }
}

pub(crate) struct Call;

impl SimplePluginCommand for Call {
    type Plugin = NixPlugin;

    fn name(&self) -> &str {
        "nix call"
    }

    fn description(&self) -> &str {
        "Call a pipeline Nix function with typed Nushell or Nix arguments."
    }

    fn signature(&self) -> Signature {
        Signature::build(SimplePluginCommand::name(self))
            .required("argument", SyntaxShape::Any, "first function argument")
            .rest(
                "arguments",
                SyntaxShape::Any,
                "one or more function arguments",
            )
            .input_output_type(
                Type::Custom("NixValue".into()),
                Type::Custom("NixValue".into()),
            )
            .category(Category::Experimental)
    }

    fn run(
        &self,
        plugin: &NixPlugin,
        engine: &EngineInterface,
        call: &EvaluatedCall,
        input: &Value,
    ) -> Result<Value, LabeledError> {
        let function = NixValue::from_value(input)?.clone();
        let first: Value = call.req(0)?;
        let mut arguments = vec![first];
        arguments.extend(call.rest::<Value>(1)?);
        let span = call.head;
        plugin.with_handle_runtime_interruptible(
            function,
            engine.signals().clone(),
            span,
            move |runtime, function| runtime.call(function, &arguments, span),
        )
    }
}

pub(crate) struct AttrNames;

impl SimplePluginCommand for AttrNames {
    type Plugin = NixPlugin;

    fn name(&self) -> &str {
        "nix attr names"
    }

    fn description(&self) -> &str {
        "List a native Nix set's attribute names without forcing their values."
    }

    fn signature(&self) -> Signature {
        Signature::build(SimplePluginCommand::name(self))
            .input_output_type(
                Type::Custom("NixValue".into()),
                Type::List(Box::new(Type::String)),
            )
            .category(Category::Experimental)
    }

    fn run(
        &self,
        plugin: &NixPlugin,
        _engine: &EngineInterface,
        _call: &EvaluatedCall,
        input: &Value,
    ) -> Result<Value, LabeledError> {
        let value = NixValue::from_value(input)?.clone();
        let span = input.span();
        plugin.with_handle_runtime(value, move |runtime, value| runtime.attr_names(value, span))
    }
}

pub(crate) struct Collect;

impl SimplePluginCommand for Collect {
    type Plugin = NixPlugin;

    fn name(&self) -> &str {
        "nix collect"
    }

    fn description(&self) -> &str {
        "Deeply force a Nix value and collect it as ordinary Nushell data."
    }

    fn signature(&self) -> Signature {
        Signature::build(SimplePluginCommand::name(self))
            .input_output_type(Type::Custom("NixValue".into()), Type::Any)
            .category(Category::Conversions)
    }

    fn run(
        &self,
        plugin: &NixPlugin,
        engine: &EngineInterface,
        _call: &EvaluatedCall,
        input: &Value,
    ) -> Result<Value, LabeledError> {
        let value = NixValue::from_value(input)?.clone();
        let span = input.span();
        plugin.with_handle_runtime_interruptible(
            value,
            engine.signals().clone(),
            span,
            move |runtime, value| runtime.convert_to_nu(value, span),
        )
    }
}

pub(crate) struct Realise;

impl SimplePluginCommand for Realise {
    type Plugin = NixPlugin;

    fn name(&self) -> &str {
        "nix realise"
    }

    fn description(&self) -> &str {
        "Realise store references in a contextual Nix string and return a plain string."
    }

    fn signature(&self) -> Signature {
        Signature::build(SimplePluginCommand::name(self))
            .input_output_type(Type::Custom("NixValue".into()), Type::Any)
            .switch(
                "details",
                "return the rendered value and physical store paths",
                None,
            )
            .category(Category::Experimental)
    }

    fn run(
        &self,
        plugin: &NixPlugin,
        engine: &EngineInterface,
        call: &EvaluatedCall,
        input: &Value,
    ) -> Result<Value, LabeledError> {
        let value = NixValue::from_value(input)?.clone();
        let details = call.has_flag("details")?;
        let span = input.span();
        plugin.with_handle_runtime_interruptible(
            value,
            engine.signals().clone(),
            span,
            move |runtime, value| runtime.realise_string(value, span, details),
        )
    }
}

pub(crate) struct TypeOf;

impl SimplePluginCommand for TypeOf {
    type Plugin = NixPlugin;

    fn name(&self) -> &str {
        "nix type"
    }

    fn description(&self) -> &str {
        "Force the outer constructor of a Nix value and return its Nix type."
    }

    fn signature(&self) -> Signature {
        Signature::build(SimplePluginCommand::name(self))
            .input_output_type(Type::Custom("NixValue".into()), Type::String)
            .category(Category::Experimental)
    }

    fn run(
        &self,
        plugin: &NixPlugin,
        _engine: &EngineInterface,
        call: &EvaluatedCall,
        input: &Value,
    ) -> Result<Value, LabeledError> {
        let value = NixValue::from_value(input)?.clone();
        let kind = plugin.with_handle_runtime(value, |runtime, value| runtime.type_name(value))?;
        Ok(Value::string(kind, call.head))
    }
}
