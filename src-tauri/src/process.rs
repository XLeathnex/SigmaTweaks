//! Running the Windows command-line tools that have no usable Rust binding.
//!
//! `sc`, `schtasks`, `powercfg`, `fsutil` and PowerShell are all invoked with
//! CREATE_NO_WINDOW, because a GUI app flashing console windows for twenty
//! consecutive tweaks looks broken.

use crate::error::{Error, Result};
use std::os::windows::process::CommandExt;
use std::process::{Command, Output};

/// CREATE_NO_WINDOW: run without allocating a console.
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

pub struct Run {
    pub status: i32,
    pub stdout: String,
    pub stderr: String,
}

impl Run {
    pub fn ok(&self) -> bool {
        self.status == 0
    }

    /// stdout and stderr together, for tools that report failures on either.
    pub fn combined(&self) -> String {
        let mut text = self.stdout.clone();
        if !self.stderr.trim().is_empty() {
            text.push('\n');
            text.push_str(&self.stderr);
        }
        text
    }
}

fn decode(bytes: &[u8]) -> String {
    // Console tools emit the OEM code page, but every string we actually parse
    // out of them (GUIDs, hex, service names, "Ultimate Performance") is ASCII,
    // so a lossy UTF-8 decode is sufficient and never fails.
    String::from_utf8_lossy(bytes).replace('\r', "")
}

fn finish(output: Output) -> Run {
    Run {
        status: output.status.code().unwrap_or(-1),
        stdout: decode(&output.stdout),
        stderr: decode(&output.stderr),
    }
}

/// Runs a program to completion, capturing its output.
pub fn run(program: &str, args: &[&str]) -> Result<Run> {
    let output = Command::new(program)
        .args(args)
        .creation_flags(CREATE_NO_WINDOW)
        .output()
        .map_err(|err| Error::new(format!("could not run {program}: {err}")))?;
    Ok(finish(output))
}

/// Runs a program and turns a non-zero exit code into an error.
pub fn run_checked(program: &str, args: &[&str]) -> Result<Run> {
    let result = run(program, args)?;
    if result.ok() {
        Ok(result)
    } else {
        let detail = result.combined();
        let detail = detail.trim();
        Err(Error::new(format!(
            "{program} exited with code {}{}",
            result.status,
            if detail.is_empty() {
                String::new()
            } else {
                format!(": {detail}")
            }
        )))
    }
}

/// Runs a PowerShell snippet. Used only where Windows exposes no other API,
/// which in practice means Appx packages and restore points.
pub fn powershell(script: &str) -> Result<Run> {
    run(
        "powershell.exe",
        &[
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            script,
        ],
    )
}
