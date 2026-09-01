//! Reading, applying and reverting tweak state.
//!
//! Everything here works from the declarative action list, so a tweak's apply,
//! revert and "is it on?" behaviour can never drift apart: they are three
//! readings of the same data.

use crate::appx;
use crate::codec;
use crate::custom;
use crate::error::Result;
use crate::inventory;
use crate::model::{Action, Mode, RegValue, State, Tweak, TweakResult, TweakStatus};
use crate::process;
use crate::registry;
use crate::services;

/// Whether the live registry value counts as applied.
///
/// A value matches if it is the one this tweak writes, or any of the extra
/// values the catalog accepts. That second list is what lets detection
/// recognise the same change made by another tool, or through the Windows UI,
/// which routinely lands on a different number with the same effect.
fn registry_applied(
    path: &str,
    name: &str,
    value: Option<&RegValue>,
    accepts: &[RegValue],
) -> bool {
    if registry::matches(path, name, value) {
        return true;
    }

    // "Should not exist" has no equivalent spellings to consider.
    if value.is_none() {
        return false;
    }

    let Ok(Some(current)) = registry::read(path, name) else {
        return false;
    };
    accepts
        .iter()
        .any(|candidate| codec::equivalent(&current, candidate))
}

/// The state of one action: `None` means "not applicable here", which is not
/// the same as "off" and must not drag the whole tweak down to Partial.
fn action_state(action: &Action) -> Option<State> {
    match action {
        Action::Registry {
            path,
            name,
            value,
            accepts,
            ..
        } => Some(if registry_applied(path, name, value.as_ref(), accepts) {
            State::Applied
        } else {
            State::NotApplied
        }),
        Action::Service {
            name,
            startup,
            accepts,
            ..
        } => {
            // A service this edition never shipped cannot be off-target.
            if !services::exists(name) {
                return None;
            }
            Some(match services::startup_type(name) {
                Some(current) if current == *startup || accepts.contains(&current) => {
                    State::Applied
                }
                Some(_) => State::NotApplied,
                None => State::Unknown,
            })
        }
        // These two read the cached inventory rather than launching a process
        // per item, which is what makes scanning the whole catalog affordable.
        Action::ScheduledTask { path, name } => {
            inventory::task_enabled(path, name).map(|enabled| {
                if enabled {
                    State::NotApplied
                } else {
                    State::Applied
                }
            })
        }
        Action::Appx { package } => Some(if inventory::package_present(package) {
            State::NotApplied
        } else {
            State::Applied
        }),
        Action::Custom { op } => Some(custom::state(*op)),
    }
}

/// Whether a tweak is currently in effect, and how much of it is.
///
/// The counts are what let the interface say "3 of 4 already set" instead of
/// an unexplained Partial, which matters most on a machine that was tweaked
/// by hand or by another tool before this app arrived.
pub fn inspect(tweak: &Tweak) -> TweakStatus {
    let states: Vec<State> = tweak.actions.iter().filter_map(action_state).collect();

    let applied = states.iter().filter(|s| **s == State::Applied).count();
    let known = states.iter().filter(|s| **s != State::Unknown).count();

    let state = if states.is_empty() || known == 0 {
        State::Unknown
    } else if states.contains(&State::Partial) {
        // A custom op that reports Partial has already aggregated its own
        // interfaces, and that answer wins over the count.
        State::Partial
    } else if applied == states.len() {
        State::Applied
    } else if applied == 0 {
        State::NotApplied
    } else {
        State::Partial
    };

    TweakStatus {
        id: tweak.id.clone(),
        state,
        reason: None,
        matched: applied as u32,
        total: states.len() as u32,
    }
}

/// Whether a tweak is currently in effect.
pub fn state(tweak: &Tweak) -> State {
    inspect(tweak).state
}

fn run_action(action: &Action, mode: Mode) -> Result<()> {
    match action {
        Action::Registry {
            path,
            name,
            value_type,
            value,
            default,
            ..
        } => {
            let wanted = match mode {
                Mode::Apply => value,
                Mode::Revert => default,
            };
            match wanted {
                Some(target) => registry::write(path, name, target, *value_type),
                // No value means the stock state is "this value does not exist".
                None => registry::delete_value(path, name),
            }
        }
        Action::Service {
            name,
            startup,
            default,
            stop,
            ..
        } => {
            let wanted = match mode {
                Mode::Apply => *startup,
                Mode::Revert => *default,
            };
            services::set_startup(name, wanted, mode == Mode::Apply && *stop)?;

            // Putting a service back to Automatic without starting it leaves
            // the machine in a state a reboot would fix but the user would not
            // understand, so start it now.
            if mode == Mode::Revert && wanted == crate::model::StartupType::Automatic {
                let _ = services::start(name);
            }
            Ok(())
        }
        Action::ScheduledTask { path, name } => {
            let outcome = services::set_task_enabled(path, name, mode == Mode::Revert);
            inventory::invalidate();
            outcome
        }
        Action::Appx { package } => match mode {
            Mode::Apply => {
                let outcome = appx::remove(package);
                inventory::invalidate();
                outcome
            }
            // Guarded by `irreversible` before we ever get here.
            Mode::Revert => Err(crate::error::Error::new(format!(
                "{package} can only be reinstalled from the Microsoft Store"
            ))),
        },
        Action::Custom { op } => match mode {
            Mode::Apply => custom::apply(*op),
            Mode::Revert => custom::revert(*op),
        },
    }
}

/// Applies or reverts one tweak, collecting every failure rather than stopping
/// at the first: a tweak that sets six values should report all six outcomes.
pub fn run(tweak: &Tweak, mode: Mode, elevated: bool) -> TweakResult {
    let refuse = |message: String| TweakResult {
        id: tweak.id.clone(),
        name: tweak.name.clone(),
        success: false,
        message,
    };

    if tweak.requires_admin && !elevated {
        return refuse("needs administrator rights".into());
    }

    if mode == Mode::Revert && tweak.irreversible {
        return refuse("this change cannot be undone by SigmaTweaks".into());
    }

    let mut failures = Vec::new();
    for action in &tweak.actions {
        if let Err(err) = run_action(action, mode) {
            failures.push(err.0);
        }
    }

    if failures.is_empty() {
        TweakResult {
            id: tweak.id.clone(),
            name: tweak.name.clone(),
            success: true,
            message: match mode {
                Mode::Apply => "applied".into(),
                Mode::Revert => "reverted".into(),
            },
        }
    } else {
        refuse(failures.join("; "))
    }
}

/// Restarts Explorer so shell tweaks take effect without a sign-out.
pub fn restart_explorer() -> Result<()> {
    let _ = process::run("taskkill.exe", &["/f", "/im", "explorer.exe"]);
    std::thread::sleep(std::time::Duration::from_millis(800));

    // Windows usually relaunches the shell itself; start it only if it did not.
    let running = process::run("tasklist.exe", &["/fi", "IMAGENAME eq explorer.exe"])
        .map(|run| run.stdout.to_ascii_lowercase().contains("explorer.exe"))
        .unwrap_or(false);

    if !running {
        let _ = process::run("explorer.exe", &[]);
    }
    Ok(())
}
