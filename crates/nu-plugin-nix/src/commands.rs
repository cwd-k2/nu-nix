use std::path::PathBuf;

use nu_plugin::{EngineInterface, EvaluatedCall, SimplePluginCommand};
use nu_protocol::{Category, LabeledError, Signature, SyntaxShape, Type, Value};

use crate::{plugin::NixPlugin, runtime::EvaluationPolicy};

mod lifecycle;
mod native_values;

pub(crate) use lifecycle::{RuntimeReset, RuntimeStatus};
pub(crate) use native_values::{AttrNames, Call, Collect, IntoNix, Realise, TypeOf};

pub(super) fn canonical_path(
    path: PathBuf,
    engine: &EngineInterface,
    span: nu_protocol::Span,
    description: &str,
    help: &str,
) -> Result<PathBuf, LabeledError> {
    let path = if path.is_absolute() {
        path
    } else {
        PathBuf::from(
            engine
                .get_current_dir()
                .map_err(|error| LabeledError::new(error.to_string()))?,
        )
        .join(path)
    };
    path.canonicalize().map_err(|error| {
        LabeledError::new(format!("cannot resolve {description}: {error}")).with_label(help, span)
    })
}

fn canonical_base(
    path: Option<PathBuf>,
    engine: &EngineInterface,
    call: &EvaluatedCall,
) -> Result<PathBuf, LabeledError> {
    canonical_path(
        path.unwrap_or_else(|| PathBuf::from(".")),
        engine,
        call.head,
        "evaluation base path",
        "base path must name an existing directory",
    )
}

pub(crate) struct Eval;

impl SimplePluginCommand for Eval {
    type Plugin = NixPlugin;

    fn name(&self) -> &str {
        "nix eval"
    }

    fn description(&self) -> &str {
        "Evaluate a Nix expression in-process and return a lazy Nix value."
    }

    fn signature(&self) -> Signature {
        Signature::build(SimplePluginCommand::name(self))
            .required(
                "expression",
                SyntaxShape::String,
                "Nix expression to evaluate",
            )
            .named(
                "path",
                SyntaxShape::Filepath,
                "base path for relative Nix paths",
                Some('p'),
            )
            .named("store", SyntaxShape::String, "Nix store URI", None)
            .input_output_type(Type::Nothing, Type::Custom("NixValue".into()))
            .category(Category::Experimental)
    }

    fn run(
        &self,
        plugin: &NixPlugin,
        engine: &EngineInterface,
        call: &EvaluatedCall,
        _input: &Value,
    ) -> Result<Value, LabeledError> {
        let expression: String = call.req(0)?;
        let path: Option<PathBuf> = call.get_flag("path")?;
        let path = canonical_base(path, engine, call)?;
        let span = call.head;
        let policy = EvaluationPolicy {
            locked: false,
            store: call.get_flag("store")?,
        };
        plugin.with_policy_runtime_interruptible(
            policy,
            engine.signals().clone(),
            span,
            move |runtime| runtime.eval(&expression, &path, span),
        )
    }
}

pub(crate) struct FlakeOutputs;

impl SimplePluginCommand for FlakeOutputs {
    type Plugin = NixPlugin;

    fn name(&self) -> &str {
        "nix flake outputs"
    }

    fn description(&self) -> &str {
        "Resolve a flake through the Nix C API and return its lazy outputs."
    }

    fn signature(&self) -> Signature {
        Signature::build(SimplePluginCommand::name(self))
            .optional(
                "reference",
                SyntaxShape::String,
                "flake reference; defaults to the current directory",
            )
            .named(
                "base-path",
                SyntaxShape::Directory,
                "base path for relative flake references",
                None,
            )
            .switch("locked", "reject flake lock changes", None)
            .named("store", SyntaxShape::String, "Nix store URI", None)
            .input_output_type(Type::Nothing, Type::Custom("NixValue".into()))
            .category(Category::Experimental)
    }

    fn run(
        &self,
        plugin: &NixPlugin,
        engine: &EngineInterface,
        call: &EvaluatedCall,
        _input: &Value,
    ) -> Result<Value, LabeledError> {
        let reference: Option<String> = call.opt(0)?;
        let base_path: Option<PathBuf> = call.get_flag("base-path")?;
        let reference = reference.unwrap_or_else(|| ".".into());
        let base_path = canonical_base(base_path, engine, call)?;
        let span = call.head;
        let policy = EvaluationPolicy {
            locked: call.has_flag("locked")?,
            store: call.get_flag("store")?,
        };
        plugin.with_policy_runtime_interruptible(
            policy,
            engine.signals().clone(),
            span,
            move |runtime| runtime.flake_outputs(&reference, &base_path, span),
        )
    }
}
