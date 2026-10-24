//! RAII owners and checked helpers for Nix C API resources.

use std::{
    ffi::{CString, c_char, c_void},
    ptr,
};

use nu_protocol::LabeledError;

use crate::ffi;

pub(super) struct Context(pub(super) *mut ffi::nix_c_context);

impl Context {
    pub(super) fn new() -> Result<Self, LabeledError> {
        let pointer = unsafe { ffi::nix_c_context_create() };
        if pointer.is_null() {
            Err(LabeledError::new("failed to allocate a Nix error context"))
        } else {
            Ok(Self(pointer))
        }
    }

    pub(super) fn check(&self, code: ffi::nix_err) -> Result<(), LabeledError> {
        if code == ffi::nix_err_NIX_OK {
            return Ok(());
        }

        let mut length = 0;
        let message = unsafe { ffi::nix_err_msg(ptr::null_mut(), self.0, &mut length) };
        let message = if message.is_null() {
            format!("Nix C API error {code}")
        } else {
            unsafe {
                String::from_utf8_lossy(std::slice::from_raw_parts(
                    message.cast::<u8>(),
                    length as usize,
                ))
                .into_owned()
            }
        };
        Err(LabeledError::new(message))
    }

    pub(super) fn last_error_or(&self, fallback: impl Into<String>) -> LabeledError {
        let code = unsafe { ffi::nix_err_code(self.0) };
        match self.check(code) {
            Err(error) => error,
            Ok(()) => LabeledError::new(fallback.into()),
        }
    }
}

impl Drop for Context {
    fn drop(&mut self) {
        unsafe { ffi::nix_c_context_free(self.0) }
    }
}

pub(super) struct OwnedNixValue {
    context: *mut ffi::nix_c_context,
    pointer: *mut ffi::nix_value,
}

impl OwnedNixValue {
    pub(super) fn new(
        context: *mut ffi::nix_c_context,
        pointer: *mut ffi::nix_value,
    ) -> Option<Self> {
        (!pointer.is_null()).then(|| Self { context, pointer })
    }

    pub(super) fn as_ptr(&self) -> *mut ffi::nix_value {
        self.pointer
    }

    pub(super) fn into_raw(mut self) -> *mut ffi::nix_value {
        std::mem::replace(&mut self.pointer, ptr::null_mut())
    }
}

impl Drop for OwnedNixValue {
    fn drop(&mut self) {
        if !self.pointer.is_null() {
            unsafe { ffi::nix_value_decref(self.context, self.pointer) };
        }
    }
}

macro_rules! owned_pointer {
    ($name:ident, $pointer:ty, $free:path) => {
        pub(super) struct $name(*mut $pointer);

        impl $name {
            pub(super) fn new(pointer: *mut $pointer) -> Option<Self> {
                (!pointer.is_null()).then(|| Self(pointer))
            }

            pub(super) fn as_ptr(&self) -> *mut $pointer {
                self.0
            }
        }

        impl Drop for $name {
            fn drop(&mut self) {
                unsafe { $free(self.0) }
            }
        }
    };
}

owned_pointer!(OwnedStore, ffi::Store, ffi::nix_store_free);
owned_pointer!(
    OwnedFetchSettings,
    ffi::nix_fetchers_settings,
    ffi::nix_fetchers_settings_free
);
owned_pointer!(
    OwnedFlakeSettings,
    ffi::nix_flake_settings,
    ffi::nix_flake_settings_free
);
owned_pointer!(
    OwnedEvalStateBuilder,
    ffi::nix_eval_state_builder,
    ffi::nix_eval_state_builder_free
);
owned_pointer!(OwnedEvalState, ffi::EvalState, ffi::nix_state_free);
owned_pointer!(
    OwnedListBuilder,
    ffi::ListBuilder,
    ffi::nix_list_builder_free
);
owned_pointer!(
    OwnedBindingsBuilder,
    ffi::BindingsBuilder,
    ffi::nix_bindings_builder_free
);
owned_pointer!(
    OwnedFlakeParseFlags,
    ffi::nix_flake_reference_parse_flags,
    ffi::nix_flake_reference_parse_flags_free
);
owned_pointer!(
    OwnedFlakeReference,
    ffi::nix_flake_reference,
    ffi::nix_flake_reference_free
);
owned_pointer!(
    OwnedFlakeLockFlags,
    ffi::nix_flake_lock_flags,
    ffi::nix_flake_lock_flags_free
);
owned_pointer!(
    OwnedLockedFlake,
    ffi::nix_locked_flake,
    ffi::nix_locked_flake_free
);
owned_pointer!(
    OwnedRealisedString,
    ffi::nix_realised_string,
    ffi::nix_realised_string_free
);

pub(super) fn c_string(value: &str, description: &str) -> Result<CString, LabeledError> {
    CString::new(value)
        .map_err(|_| LabeledError::new(format!("{description} cannot contain a NUL byte")))
}

pub(super) unsafe extern "C" fn copy_string(
    start: *const c_char,
    length: u32,
    user_data: *mut c_void,
) {
    if start.is_null() || user_data.is_null() {
        return;
    }
    let destination = unsafe { &mut *user_data.cast::<Vec<u8>>() };
    let source = unsafe { std::slice::from_raw_parts(start.cast::<u8>(), length as usize) };
    destination.extend_from_slice(source);
}

#[cfg(test)]
mod tests {
    use std::{
        ffi::c_void,
        ptr,
        sync::atomic::{AtomicUsize, Ordering},
    };

    use super::copy_string;

    static FREES: AtomicUsize = AtomicUsize::new(0);

    pub(super) struct TestResource;

    unsafe extern "C" fn free_test_resource(pointer: *mut TestResource) {
        FREES.fetch_add(1, Ordering::SeqCst);
        drop(unsafe { Box::from_raw(pointer) });
    }

    owned_pointer!(OwnedTestResource, TestResource, free_test_resource);

    fn fail_after_acquire() -> Result<(), ()> {
        let resource = OwnedTestResource::new(Box::into_raw(Box::new(TestResource))).ok_or(())?;
        assert!(!resource.as_ptr().is_null());
        Err(())
    }

    #[test]
    fn malformed_null_resource_is_rejected_without_cleanup() {
        FREES.store(0, Ordering::SeqCst);
        assert!(OwnedTestResource::new(ptr::null_mut()).is_none());
        assert_eq!(FREES.load(Ordering::SeqCst), 0);
    }

    #[test]
    fn acquired_resource_is_cleaned_on_failure() {
        FREES.store(0, Ordering::SeqCst);
        assert_eq!(fail_after_acquire(), Err(()));
        assert_eq!(FREES.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn malformed_copy_callback_arguments_are_ignored() {
        let mut destination = vec![1_u8];
        unsafe {
            copy_string(
                ptr::null(),
                4,
                (&mut destination as *mut Vec<u8>).cast::<c_void>(),
            );
            copy_string(b"data".as_ptr().cast(), 4, ptr::null_mut());
        }
        assert_eq!(destination, vec![1]);
    }
}
