mod commands;
mod ffi;
mod plugin;
mod runtime;
mod value;

use nu_plugin::{MsgPackSerializer, serve_plugin};
use plugin::NixPlugin;

fn main() {
    serve_plugin(&NixPlugin::new(), MsgPackSerializer {})
}
