//! Service startup types and scheduled task states.

use crate::error::{Error, Result};
use crate::model::StartupType;
use crate::model::{RegValue, ValueType};
use crate::process;
use crate::registry;

pub fn is_protected(name: &str) -> bool {
    crate::protected::is_protected_service(name)
}

fn service_key(name: &str) -> String {
    format!("HKLM:\\SYSTEM\\CurrentControlSet\\Services\\{name}")
}

/// True when the service is installed on this edition of Windows.
pub fn exists(name: &str) -> bool {
    registry::read(&service_key(name), "Start")
        .ok()
        .flatten()
        .is_some()
}

/// The configured startup type, read from the registry because that is what
/// the service control manager itself reads.
pub fn startup_type(name: &str) -> Option<StartupType> {
    match registry::read(&service_key(name), "Start").ok().flatten() {
        Some(RegValue::Int(value)) => StartupType::from_start_value(value as u32),
        _ => None,
    }
}

pub fn is_running(name: &str) -> bool {
    match process::run("sc.exe", &["query", name]) {
        Ok(result) => result.ok() && result.stdout.contains("RUNNING"),
        Err(_) => false,
    }
}

/// Sets a service's startup type, and optionally stops it now.
///
/// `sc config` is tried first. Some services (DiagTrack is the usual example)
/// deny configuration changes even to an elevated administrator through the
/// service control manager, while still allowing the registry write that the
/// SCM reads at boot, so that is the fallback.
pub fn set_startup(name: &str, startup: StartupType, stop: bool) -> Result<()> {
    if is_protected(name) {
        return Err(Error::new(format!(
            "'{name}' is a protected service and will not be reconfigured"
        )));
    }

    if !exists(name) {
        // Editions differ in which services ship. Nothing to do is success.
        return Ok(());
    }

    if stop && is_running(name) {
        let _ = process::run("sc.exe", &["stop", name]);
    }

    let configured = process::run("sc.exe", &["config", name, "start=", startup.sc_argument()]);

    let sc_worked = matches!(configured, Ok(ref run) if run.ok());
    if sc_worked {
        return Ok(());
    }

    registry::write(
        &service_key(name),
        "Start",
        &RegValue::Int(i64::from(startup.start_value())),
        ValueType::Dword,
    )
}

pub fn start(name: &str) -> Result<()> {
    if !exists(name) || is_running(name) {
        return Ok(());
    }
    let _ = process::run("sc.exe", &["start", name]);
    Ok(())
}

/// A scheduled task's full path, as schtasks expects it.
fn task_path(path: &str, name: &str) -> String {
    format!("{}\\{}", path.trim_end_matches('\\'), name)
}

/// `Some(true)` when enabled, `Some(false)` when disabled, `None` when the
/// task does not exist on this build.
pub fn task_enabled(path: &str, name: &str) -> Option<bool> {
    let full = task_path(path, name);
    let result = process::run("schtasks.exe", &["/Query", "/TN", &full, "/FO", "LIST"]).ok()?;
    if !result.ok() {
        return None;
    }

    let status = result.stdout.lines().find(|line| {
        line.trim_start()
            .to_ascii_lowercase()
            .starts_with("status:")
    })?;
    let value = status.split_once(':')?.1.trim().to_ascii_lowercase();
    Some(value != "disabled")
}

/// Enables or disables a scheduled task. Builds differ in which tasks ship, so
/// a task that is not there is not an error.
pub fn set_task_enabled(path: &str, name: &str, enabled: bool) -> Result<()> {
    let full = task_path(path, name);
    let flag = if enabled { "/ENABLE" } else { "/DISABLE" };
    let result = process::run("schtasks.exe", &["/Change", "/TN", &full, flag])?;

    if result.ok() || task_enabled(path, name).is_none() {
        Ok(())
    } else {
        Err(Error::new(format!(
            "could not {} scheduled task {full}",
            if enabled { "enable" } else { "disable" }
        )))
    }
}
