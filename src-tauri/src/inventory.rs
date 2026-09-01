//! Cached machine inventory for state detection.
//!
//! Detecting whether a tweak is already applied has to be fast enough to run
//! over the whole catalog at startup, because the most useful thing this app
//! can tell you is what someone already did to this machine before it was
//! installed. Reading it one item at a time does not survive that: the Debloat
//! category alone would be 28 PowerShell launches.
//!
//! So the two slow sources - Store packages and scheduled tasks - are each
//! read once into a snapshot and cached. The snapshot is dropped after any
//! batch that could have changed it.

use crate::error::Result;
use crate::parse::{parse_task_row, pattern_matches};
use crate::process;
use std::collections::{HashMap, HashSet};
use std::sync::{Mutex, OnceLock};

#[derive(Debug, Default)]
pub struct Packages {
    /// Package family names installed for the current user, lowercased.
    pub installed: HashSet<String>,
    /// Display names still provisioned for new users, lowercased.
    ///
    /// Empty when the app is not elevated, because the query needs admin. A
    /// package is then judged on the installed list alone, which is the
    /// honest answer rather than a guess.
    pub provisioned: HashSet<String>,
    /// Whether the provisioned list could actually be read.
    pub provisioned_known: bool,
}

#[derive(Debug, Default)]
pub struct Tasks {
    /// Full task path, lowercased, to whether it is enabled.
    pub states: HashMap<String, bool>,
}

fn packages_cache() -> &'static Mutex<Option<&'static Packages>> {
    static CACHE: OnceLock<Mutex<Option<&'static Packages>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(None))
}

fn tasks_cache() -> &'static Mutex<Option<&'static Tasks>> {
    static CACHE: OnceLock<Mutex<Option<&'static Tasks>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(None))
}

/// Forgets both snapshots. Called after anything that removes a package or
/// changes a task, so the next read reflects what actually happened.
pub fn invalidate() {
    if let Ok(mut guard) = packages_cache().lock() {
        *guard = None;
    }
    if let Ok(mut guard) = tasks_cache().lock() {
        *guard = None;
    }
}

/// Every Store package on the machine, read once.
pub fn packages() -> &'static Packages {
    if let Ok(guard) = packages_cache().lock() {
        if let Some(cached) = *guard {
            return cached;
        }
    }

    let fresh: &'static Packages = Box::leak(Box::new(read_packages()));
    if let Ok(mut guard) = packages_cache().lock() {
        *guard = Some(fresh);
    }
    fresh
}

fn read_packages() -> Packages {
    // A sentinel keeps the two lists apart in one round trip. Failure of
    // either half leaves that half empty rather than failing the whole scan.
    const SCRIPT: &str = "$ErrorActionPreference='SilentlyContinue';\
         (Get-AppxPackage).Name -join \"`n\";\
         Write-Output '===PROVISIONED===';\
         (Get-AppxProvisionedPackage -Online).DisplayName -join \"`n\"";

    let Ok(run) = process::powershell(SCRIPT) else {
        return Packages::default();
    };

    let (installed_text, provisioned_text) = run
        .stdout
        .split_once("===PROVISIONED===")
        .unwrap_or((run.stdout.as_str(), ""));

    let collect = |text: &str| -> HashSet<String> {
        text.lines()
            .map(|line| line.trim().to_ascii_lowercase())
            .filter(|line| !line.is_empty())
            .collect()
    };

    let provisioned = collect(provisioned_text);
    Packages {
        installed: collect(installed_text),
        provisioned_known: !provisioned.is_empty(),
        provisioned,
    }
}

/// Every scheduled task and whether it is enabled, read once.
pub fn tasks() -> &'static Tasks {
    if let Ok(guard) = tasks_cache().lock() {
        if let Some(cached) = *guard {
            return cached;
        }
    }

    let fresh: &'static Tasks = Box::leak(Box::new(read_tasks()));
    if let Ok(mut guard) = tasks_cache().lock() {
        *guard = Some(fresh);
    }
    fresh
}

fn read_tasks() -> Tasks {
    // The three-column CSV form is "TaskName","Next Run Time","Status", which
    // is exactly what detection needs and one process instead of one per task.
    let Ok(run) = process::run("schtasks.exe", &["/Query", "/FO", "CSV", "/NH"]) else {
        return Tasks::default();
    };

    Tasks {
        states: run.stdout.lines().filter_map(parse_task_row).collect(),
    }
}

pub use crate::parse::pattern_matches as matches_pattern;

/// Whether a package is still present, either installed or provisioned.
pub fn package_present(pattern: &str) -> bool {
    let snapshot = packages();
    snapshot
        .installed
        .iter()
        .chain(snapshot.provisioned.iter())
        .any(|name| pattern_matches(pattern, name))
}

/// `None` when the task does not exist on this build, which is not the same
/// as it being enabled.
pub fn task_enabled(path: &str, name: &str) -> Option<bool> {
    let full = format!("{}\\{}", path.trim_end_matches('\\'), name).to_ascii_lowercase();
    tasks().states.get(&full).copied()
}

/// Forces both snapshots to be built now, so the first category the user opens
/// is not the one that pays for them.
pub fn warm() -> Result<()> {
    let _ = packages();
    let _ = tasks();
    Ok(())
}
