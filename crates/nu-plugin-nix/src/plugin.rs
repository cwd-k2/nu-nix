use std::{
    any::Any,
    fs::File,
    io::Read,
    sync::mpsc::{self, RecvTimeoutError, SyncSender},
    thread::{self, JoinHandle},
    time::Duration,
};

use nu_plugin::{EngineInterface, Plugin, PluginCommand};
use nu_protocol::{CustomValue, LabeledError, Signals, Span, Spanned, Value, casing::Casing};

use crate::{
    commands::{
        AttrNames, Call, Collect, Eval, FlakeOutputs, IntoNix, Realise, RuntimeReset,
        RuntimeStatus, TypeOf,
    },
    runtime::{EvaluationPolicy, Runtime},
    value::NixValue,
};

pub struct NixPlugin {
    worker: RuntimeWorker,
}

struct RuntimeSlot {
    session: [u8; 16],
    generation: u64,
    runtime: Option<Runtime>,
    policy: Option<EvaluationPolicy>,
}

type WorkerValue = Box<dyn Any + Send>;
type WorkerOperation =
    Box<dyn FnOnce(&mut RuntimeSlot) -> Result<WorkerValue, LabeledError> + Send>;
type WorkerResult = Result<WorkerValue, LabeledError>;

struct WorkerRequest {
    operation: WorkerOperation,
    response: mpsc::Sender<WorkerResult>,
}

struct RuntimeWorker {
    sender: Option<SyncSender<WorkerRequest>>,
    thread: Option<JoinHandle<()>>,
}

impl RuntimeWorker {
    fn new(session: [u8; 16]) -> Self {
        let (sender, receiver) = mpsc::sync_channel::<WorkerRequest>(0);
        let thread = thread::Builder::new()
            .name("nu-nix-evaluator".into())
            .spawn(move || {
                let mut slot = RuntimeSlot {
                    session,
                    generation: 0,
                    runtime: None,
                    policy: None,
                };
                while let Ok(request) = receiver.recv() {
                    let result = (request.operation)(&mut slot);
                    if request.response.send(result).is_err() {
                        // An interrupted caller abandoned this result. Reset the
                        // arena so handles created by the abandoned operation do
                        // not remain live without a Nushell owner.
                        slot.runtime = None;
                        slot.policy = None;
                        let Some(generation) = slot.generation.checked_add(1) else {
                            // Continuing at the same generation could make a
                            // stale handle alias a future arena slot.
                            return;
                        };
                        slot.generation = generation;
                    }
                }
            })
            .expect("the Nix evaluator worker can be started");
        Self {
            sender: Some(sender),
            thread: Some(thread),
        }
    }

    fn execute<T: Send + 'static>(
        &self,
        operation: impl FnOnce(&mut RuntimeSlot) -> Result<T, LabeledError> + Send + 'static,
    ) -> Result<T, LabeledError> {
        let result = self.submit(operation)?;
        result
            .recv()
            .map_err(|_| worker_stopped())??
            .downcast::<T>()
            .map(|value| *value)
            .map_err(|_| LabeledError::new("Nix evaluator worker returned an invalid response"))
    }

    fn execute_interruptible<T: Send + 'static>(
        &self,
        signals: Signals,
        span: Span,
        operation: impl FnOnce(&mut RuntimeSlot) -> Result<T, LabeledError> + Send + 'static,
    ) -> Result<T, LabeledError> {
        let result = self.submit(operation)?;
        loop {
            if signals.interrupted() {
                return Err(LabeledError::new("Nix operation interrupted")
                    .with_label("the native result was abandoned safely", span)
                    .with_help(
                        "The evaluator runtime will reset after the in-flight Nix call returns.",
                    ));
            }
            match result.recv_timeout(Duration::from_millis(25)) {
                Ok(result) => {
                    return result?.downcast::<T>().map(|value| *value).map_err(|_| {
                        LabeledError::new("Nix evaluator worker returned an invalid response")
                    });
                }
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => return Err(worker_stopped()),
            }
        }
    }

    fn submit<T: Send + 'static>(
        &self,
        operation: impl FnOnce(&mut RuntimeSlot) -> Result<T, LabeledError> + Send + 'static,
    ) -> Result<mpsc::Receiver<WorkerResult>, LabeledError> {
        let (response, result) = mpsc::channel();
        let request = WorkerRequest {
            operation: Box::new(move |slot| {
                operation(slot).map(|value| Box::new(value) as WorkerValue)
            }),
            response,
        };
        self.sender
            .as_ref()
            .ok_or_else(worker_stopped)?
            .send(request)
            .map_err(|_| worker_stopped())?;
        Ok(result)
    }
}

impl Drop for RuntimeWorker {
    fn drop(&mut self) {
        self.sender.take();
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

fn worker_stopped() -> LabeledError {
    LabeledError::new("Nix evaluator worker stopped unexpectedly")
}

impl NixPlugin {
    pub fn new() -> Self {
        let mut session = [0_u8; 16];
        File::open("/dev/urandom")
            .and_then(|mut source| source.read_exact(&mut session))
            .expect("the Linux random device is available");
        Self {
            worker: RuntimeWorker::new(session),
        }
    }

    pub(crate) fn with_runtime<T: Send + 'static>(
        &self,
        operation: impl FnOnce(&mut Runtime) -> Result<T, LabeledError> + Send + 'static,
    ) -> Result<T, LabeledError> {
        self.worker.execute(move |slot| {
            if slot.runtime.is_none() {
                let policy = EvaluationPolicy::default();
                slot.runtime = Some(Runtime::new(slot.session, slot.generation, &policy)?);
                slot.policy = Some(policy);
            }
            let runtime = slot
                .runtime
                .as_mut()
                .ok_or_else(|| LabeledError::new("Nix runtime initialization failed"))?;
            operation(runtime)
        })
    }

    pub(crate) fn with_policy_runtime_interruptible<T: Send + 'static>(
        &self,
        policy: EvaluationPolicy,
        signals: Signals,
        span: Span,
        operation: impl FnOnce(&mut Runtime) -> Result<T, LabeledError> + Send + 'static,
    ) -> Result<T, LabeledError> {
        self.worker
            .execute_interruptible(signals, span, move |slot| {
                if slot.policy.as_ref() != Some(&policy) {
                    slot.runtime = None;
                    slot.generation = slot.generation.checked_add(1).ok_or_else(|| {
                        LabeledError::new("Nix runtime generation space has been exhausted")
                    })?;
                    slot.runtime = Some(Runtime::new(slot.session, slot.generation, &policy)?);
                    slot.policy = Some(policy);
                }
                let runtime = slot
                    .runtime
                    .as_mut()
                    .ok_or_else(|| LabeledError::new("Nix runtime initialization failed"))?;
                operation(runtime)
            })
    }

    pub(crate) fn with_handle_runtime_interruptible<T: Send + 'static>(
        &self,
        handle: NixValue,
        signals: Signals,
        span: Span,
        operation: impl FnOnce(&mut Runtime, &NixValue) -> Result<T, LabeledError> + Send + 'static,
    ) -> Result<T, LabeledError> {
        self.worker
            .execute_interruptible(signals, span, move |slot| {
                handle.validate_identity(slot.session, slot.generation)?;
                let runtime = slot
                    .runtime
                    .as_mut()
                    .ok_or_else(|| LabeledError::new("Nix value runtime is no longer available"))?;
                operation(runtime, &handle)
            })
    }

    pub(crate) fn with_handle_runtime<T: Send + 'static>(
        &self,
        handle: NixValue,
        operation: impl FnOnce(&mut Runtime, &NixValue) -> Result<T, LabeledError> + Send + 'static,
    ) -> Result<T, LabeledError> {
        self.worker.execute(move |slot| {
            handle.validate_identity(slot.session, slot.generation)?;
            let runtime = slot
                .runtime
                .as_mut()
                .ok_or_else(|| LabeledError::new("Nix value runtime is no longer available"))?;
            operation(runtime, &handle)
        })
    }

    pub(crate) fn runtime_status(&self, span: nu_protocol::Span) -> Result<Value, LabeledError> {
        self.worker.execute(move |slot| {
            let mut record = nu_protocol::Record::new();
            record.push("initialized", Value::bool(slot.runtime.is_some(), span));
            record.push(
                "session",
                Value::string(
                    slot.session
                        .iter()
                        .map(|byte| format!("{byte:02x}"))
                        .collect::<String>(),
                    span,
                ),
            );
            if let Some(policy) = &slot.policy {
                let mut value = nu_protocol::Record::new();
                value.push("locked", Value::bool(policy.locked, span));
                value.push(
                    "store",
                    policy
                        .store
                        .as_ref()
                        .map_or_else(|| Value::nothing(span), |store| Value::string(store, span)),
                );
                record.push("policy", Value::record(value, span));
            } else {
                record.push("policy", Value::nothing(span));
            }
            record.push("generation", Value::int(slot.generation as i64, span));
            record.push(
                "handles",
                Value::int(
                    slot.runtime.as_ref().map_or(0, Runtime::handle_count) as i64,
                    span,
                ),
            );
            record.push(
                "next_id",
                Value::int(
                    slot.runtime.as_ref().map_or(0, Runtime::next_id) as i64,
                    span,
                ),
            );
            let mut capabilities = nu_protocol::Record::new();
            capabilities.push(
                "cancellation",
                Value::string("safe-abandon-and-reset", span),
            );
            capabilities.push("progress", Value::bool(false, span));
            capabilities.push("perRequestEvaluationPolicy", Value::bool(true, span));
            capabilities.push("explicitStoreSelection", Value::bool(true, span));
            record.push("capabilities", Value::record(capabilities, span));
            Ok(Value::record(record, span))
        })
    }

    pub(crate) fn reset_runtime(&self) -> Result<(), LabeledError> {
        self.worker.execute(|slot| {
            let generation = slot.generation.checked_add(1).ok_or_else(|| {
                LabeledError::new("Nix runtime generation space has been exhausted")
            })?;
            slot.runtime = None;
            slot.policy = None;
            slot.generation = generation;
            Ok(())
        })
    }

    fn release_dropped_value(&self, handle: NixValue) -> Result<(), LabeledError> {
        self.worker.execute(move |slot| {
            if handle.session != slot.session || handle.generation != slot.generation {
                return Ok(());
            }
            if let Some(runtime) = slot.runtime.as_mut() {
                runtime.release(&handle)?;
            }
            Ok(())
        })
    }
}

impl Plugin for NixPlugin {
    fn version(&self) -> String {
        env!("CARGO_PKG_VERSION").into()
    }

    fn commands(&self) -> Vec<Box<dyn PluginCommand<Plugin = Self>>> {
        vec![
            Box::new(Eval),
            Box::new(IntoNix),
            Box::new(Call),
            Box::new(FlakeOutputs),
            Box::new(AttrNames),
            Box::new(Realise),
            Box::new(Collect),
            Box::new(TypeOf),
            Box::new(RuntimeStatus),
            Box::new(RuntimeReset),
        ]
    }

    fn custom_value_to_base_value(
        &self,
        _engine: &EngineInterface,
        custom_value: Spanned<Box<dyn CustomValue>>,
    ) -> Result<Value, LabeledError> {
        custom_value
            .item
            .as_any()
            .downcast_ref::<NixValue>()
            .ok_or_else(|| LabeledError::new("custom value is not owned by the Nix plugin"))?;
        Ok(Value::string("<lazy Nix value>", custom_value.span))
    }

    fn custom_value_follow_path_int(
        &self,
        _engine: &EngineInterface,
        custom_value: Spanned<Box<dyn CustomValue>>,
        index: Spanned<usize>,
        optional: bool,
    ) -> Result<Value, LabeledError> {
        let value = custom_value
            .item
            .as_any()
            .downcast_ref::<NixValue>()
            .ok_or_else(|| LabeledError::new("custom value is not owned by the Nix plugin"))?
            .clone();
        self.with_handle_runtime(value, move |runtime, value| {
            runtime.follow_index(value, index.item, index.span, optional)
        })
    }

    fn custom_value_follow_path_string(
        &self,
        _engine: &EngineInterface,
        custom_value: Spanned<Box<dyn CustomValue>>,
        column_name: Spanned<String>,
        optional: bool,
        casing: Casing,
    ) -> Result<Value, LabeledError> {
        let value = custom_value
            .item
            .as_any()
            .downcast_ref::<NixValue>()
            .ok_or_else(|| LabeledError::new("custom value is not owned by the Nix plugin"))?
            .clone();
        self.with_handle_runtime(value, move |runtime, value| {
            runtime.follow_attr(
                value,
                &column_name.item,
                column_name.span,
                optional,
                matches!(casing, Casing::Insensitive),
            )
        })
    }

    fn custom_value_dropped(
        &self,
        _engine: &EngineInterface,
        custom_value: Box<dyn CustomValue>,
    ) -> Result<(), LabeledError> {
        let value = custom_value
            .as_any()
            .downcast_ref::<NixValue>()
            .ok_or_else(|| LabeledError::new("custom value is not owned by the Nix plugin"))?
            .clone();
        self.release_dropped_value(value)
    }
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, atomic::AtomicBool};

    use nu_protocol::{Signals, Span};

    use super::RuntimeWorker;

    #[test]
    fn interrupted_operation_resets_before_the_next_request() {
        let worker = RuntimeWorker::new([0; 16]);
        let flag = Arc::new(AtomicBool::new(true));
        let (release, wait) = std::sync::mpsc::channel();
        let result =
            worker.execute_interruptible(Signals::new(flag), Span::unknown(), move |_slot| {
                wait.recv().expect("the test operation can be released");
                Ok::<_, nu_protocol::LabeledError>(42)
            });
        assert!(result.is_err());

        release.send(()).expect("the worker is still running");
        let generation = worker
            .execute(|slot| Ok::<_, nu_protocol::LabeledError>(slot.generation))
            .expect("a request after cancellation succeeds");
        assert_eq!(generation, 1);
    }
}
