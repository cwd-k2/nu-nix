use nu_protocol::{CustomValue, LabeledError, ShellError, Span, Value};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct NixValue {
    pub session: [u8; 16],
    pub generation: u64,
    pub id: u64,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum HandleIdentityError {
    Session,
    Generation,
}

impl NixValue {
    pub fn into_value(self, span: Span) -> Value {
        Value::custom(Box::new(self), span)
    }

    pub fn from_value(value: &Value) -> Result<&Self, LabeledError> {
        value
            .as_custom_value()
            .map_err(LabeledError::from)?
            .as_any()
            .downcast_ref::<Self>()
            .ok_or_else(|| {
                LabeledError::new("expected a Nix value")
                    .with_label(format!("got {}", value.get_type()), value.span())
            })
    }

    pub(crate) fn validate_identity(
        &self,
        session: [u8; 16],
        generation: u64,
    ) -> Result<(), HandleIdentityError> {
        if self.session != session {
            Err(HandleIdentityError::Session)
        } else if self.generation != generation {
            Err(HandleIdentityError::Generation)
        } else {
            Ok(())
        }
    }
}

impl From<HandleIdentityError> for LabeledError {
    fn from(error: HandleIdentityError) -> Self {
        match error {
            HandleIdentityError::Session => {
                LabeledError::new("Nix value belongs to another plugin session")
            }
            HandleIdentityError::Generation => LabeledError::new(
                "Nix value belongs to an expired runtime generation",
            )
            .with_help("Evaluate or convert the value again after `nix debug runtime reset`."),
        }
    }
}

#[typetag::serde]
impl CustomValue for NixValue {
    fn clone_value(&self, span: Span) -> Value {
        self.clone().into_value(span)
    }

    fn type_name(&self) -> String {
        "NixValue".into()
    }

    fn to_base_value(&self, span: Span) -> Result<Value, ShellError> {
        Err(
            LabeledError::new("Nix values are owned by the native plugin")
                .with_label("use `nix collect` to force and convert it", span)
                .into(),
        )
    }

    fn notify_plugin_on_drop(&self) -> bool {
        true
    }

    fn as_any(&self) -> &dyn std::any::Any {
        self
    }

    fn as_mut_any(&mut self) -> &mut dyn std::any::Any {
        self
    }
}

#[cfg(test)]
mod tests {
    use super::{HandleIdentityError, NixValue};

    #[test]
    fn handle_identity_distinguishes_session_and_generation() {
        let value = NixValue {
            session: [1; 16],
            generation: 3,
            id: 7,
        };
        assert_eq!(value.validate_identity([1; 16], 3), Ok(()));
        assert_eq!(
            value.validate_identity([2; 16], 3),
            Err(HandleIdentityError::Session)
        );
        assert_eq!(
            value.validate_identity([1; 16], 4),
            Err(HandleIdentityError::Generation)
        );
    }
}
