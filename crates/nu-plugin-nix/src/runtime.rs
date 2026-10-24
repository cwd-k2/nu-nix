//! Composition root for the single native Nix evaluator runtime.

use std::{collections::BTreeMap, ffi::CString, ptr};

use nu_protocol::LabeledError;

use crate::ffi;

mod arena;
mod conversion;
mod evaluation;
mod limits;
mod realisation;
mod resources;

use resources::{
    Context, OwnedEvalState, OwnedEvalStateBuilder, OwnedFetchSettings, OwnedFlakeSettings,
    OwnedStore,
};

pub struct Runtime {
    values: BTreeMap<u64, *mut ffi::nix_value>,
    state: OwnedEvalState,
    flake_settings: OwnedFlakeSettings,
    fetch_settings: OwnedFetchSettings,
    store: OwnedStore,
    context: Context,
    next_id: u64,
    session: [u8; 16],
    generation: u64,
    policy: EvaluationPolicy,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct EvaluationPolicy {
    pub locked: bool,
    pub store: Option<String>,
}

impl Runtime {
    pub fn new(
        session: [u8; 16],
        generation: u64,
        policy: &EvaluationPolicy,
    ) -> Result<Self, LabeledError> {
        let context = Context::new()?;
        unsafe {
            context.check(ffi::nix_libutil_init(context.0))?;
            context.check(ffi::nix_setting_set(
                context.0,
                c"extra-experimental-features".as_ptr(),
                c"nix-command flakes".as_ptr(),
            ))?;
            context.check(ffi::nix_libstore_init(context.0))?;
            context.check(ffi::nix_libexpr_init(context.0))?;
        }

        let store_uri = policy
            .store
            .as_deref()
            .map(|uri| CString::new(uri).map_err(|_| LabeledError::new("store URI contains NUL")))
            .transpose()?;
        let store = OwnedStore::new(unsafe {
            ffi::nix_store_open(
                context.0,
                store_uri.as_ref().map_or(ptr::null(), |uri| uri.as_ptr()),
                ptr::null_mut(),
            )
        })
        .ok_or_else(|| context.last_error_or("failed to open the configured Nix store"))?;
        let fetch_settings =
            OwnedFetchSettings::new(unsafe { ffi::nix_fetchers_settings_new(context.0) })
                .ok_or_else(|| {
                    context.last_error_or("failed to initialize Nix fetcher settings")
                })?;
        let flake_settings =
            OwnedFlakeSettings::new(unsafe { ffi::nix_flake_settings_new(context.0) })
                .ok_or_else(|| context.last_error_or("failed to initialize Nix flake settings"))?;
        let builder = OwnedEvalStateBuilder::new(unsafe {
            ffi::nix_eval_state_builder_new(context.0, store.as_ptr())
        })
        .ok_or_else(|| context.last_error_or("failed to create a Nix evaluator builder"))?;
        context.check(unsafe { ffi::nix_eval_state_builder_load(context.0, builder.as_ptr()) })?;
        context.check(unsafe {
            ffi::nix_flake_settings_add_to_eval_state_builder(
                context.0,
                flake_settings.as_ptr(),
                builder.as_ptr(),
            )
        })?;
        let state =
            OwnedEvalState::new(unsafe { ffi::nix_eval_state_build(context.0, builder.as_ptr()) })
                .ok_or_else(|| context.last_error_or("failed to create a Nix evaluator state"))?;

        Ok(Self {
            values: BTreeMap::new(),
            state,
            flake_settings,
            fetch_settings,
            store,
            context,
            next_id: 0,
            session,
            generation,
            policy: policy.clone(),
        })
    }

    pub fn handle_count(&self) -> usize {
        self.values.len()
    }

    pub fn next_id(&self) -> u64 {
        self.next_id
    }

    pub fn policy(&self) -> &EvaluationPolicy {
        &self.policy
    }
}

impl Drop for Runtime {
    fn drop(&mut self) {
        unsafe {
            for (_, value) in std::mem::take(&mut self.values) {
                ffi::nix_value_decref(self.context.0, value);
            }
        }
    }
}
