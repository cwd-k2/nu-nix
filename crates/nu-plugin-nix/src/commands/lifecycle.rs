use nu_plugin::{EngineInterface, EvaluatedCall, SimplePluginCommand};
use nu_protocol::{Category, LabeledError, Signature, Type, Value};

use crate::plugin::NixPlugin;

pub(crate) struct RuntimeStatus;

impl SimplePluginCommand for RuntimeStatus {
    type Plugin = NixPlugin;

    fn name(&self) -> &str {
        "nix debug runtime status"
    }

    fn description(&self) -> &str {
        "Diagnose the native evaluator generation and live handle count."
    }

    fn signature(&self) -> Signature {
        Signature::build(SimplePluginCommand::name(self))
            .input_output_type(
                Type::Nothing,
                Type::Record(
                    [
                        ("initialized", Type::Bool),
                        ("session", Type::String),
                        ("generation", Type::Int),
                        ("handles", Type::Int),
                        ("next_id", Type::Int),
                    ]
                    .into(),
                ),
            )
            .category(Category::Debug)
    }

    fn run(
        &self,
        plugin: &NixPlugin,
        _engine: &EngineInterface,
        call: &EvaluatedCall,
        _input: &Value,
    ) -> Result<Value, LabeledError> {
        plugin.runtime_status(call.head)
    }
}

pub(crate) struct RuntimeReset;

impl SimplePluginCommand for RuntimeReset {
    type Plugin = NixPlugin;

    fn name(&self) -> &str {
        "nix debug runtime reset"
    }

    fn description(&self) -> &str {
        "Destroy the native evaluator and invalidate every existing Nix value."
    }

    fn signature(&self) -> Signature {
        Signature::build(SimplePluginCommand::name(self))
            .input_output_type(Type::Nothing, Type::Nothing)
            .category(Category::Debug)
    }

    fn run(
        &self,
        plugin: &NixPlugin,
        _engine: &EngineInterface,
        call: &EvaluatedCall,
        _input: &Value,
    ) -> Result<Value, LabeledError> {
        plugin.reset_runtime()?;
        Ok(Value::nothing(call.head))
    }
}
