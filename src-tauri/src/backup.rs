//! Snapshots of what was there before.
//!
//! A tweak's declared defaults describe stock Windows. A snapshot describes
//! *this* machine: before any batch runs, the current value of everything it
//! is about to touch is written to disk. Restoring a snapshot therefore puts
//! back real customisations, not just Microsoft's defaults.

use crate::error::{Context, Result};
use crate::model::{Action, RegValue, StartupType, Tweak, ValueType};
use crate::registry;
use crate::services;
use chrono::Local;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Entry {
    Registry {
        path: String,
        name: String,
        existed: bool,
        value: Option<RegValue>,
        value_type: ValueType,
    },
    Service {
        name: String,
        existed: bool,
        startup: Option<StartupType>,
        running: bool,
    },
    ScheduledTask {
        path: String,
        name: String,
        enabled: Option<bool>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Snapshot {
    pub version: u32,
    pub created: String,
    pub computer: String,
    pub label: String,
    pub tweak_ids: Vec<String>,
    pub entries: Vec<Entry>,
}

#[derive(Debug, Clone, Serialize)]
pub struct BackupInfo {
    pub path: String,
    pub file_name: String,
    pub created: String,
    pub label: String,
    pub tweak_count: usize,
    pub entry_count: usize,
}

/// `%LOCALAPPDATA%\SigmaTweaks`, created on first use.
pub fn data_dir() -> Result<PathBuf> {
    let base = std::env::var("LOCALAPPDATA")
        .map_err(|_| crate::error::Error::new("LOCALAPPDATA is not set"))?;
    let dir = PathBuf::from(base).join("SigmaTweaks");
    std::fs::create_dir_all(&dir).context("creating the SigmaTweaks data directory")?;
    Ok(dir)
}

fn backup_dir() -> Result<PathBuf> {
    let dir = data_dir()?.join("backups");
    std::fs::create_dir_all(&dir).context("creating the backup directory")?;
    Ok(dir)
}

/// Records the live state of everything one tweak declares.
fn capture_tweak(tweak: &Tweak) -> Vec<Entry> {
    let mut entries = Vec::new();

    for action in &tweak.actions {
        match action {
            Action::Registry {
                path,
                name,
                value_type,
                ..
            } => {
                let current = registry::read_typed(path, name).ok().flatten();
                entries.push(Entry::Registry {
                    path: path.clone(),
                    name: name.clone(),
                    existed: current.is_some(),
                    value: current.as_ref().map(|(value, _)| value.clone()),
                    // Prefer the type Windows really used over the catalog's.
                    value_type: current.map(|(_, kind)| kind).unwrap_or(*value_type),
                });
            }
            Action::Service { name, .. } => {
                let exists = services::exists(name);
                entries.push(Entry::Service {
                    name: name.clone(),
                    existed: exists,
                    startup: if exists {
                        services::startup_type(name)
                    } else {
                        None
                    },
                    running: exists && services::is_running(name),
                });
            }
            Action::ScheduledTask { path, name } => entries.push(Entry::ScheduledTask {
                path: path.clone(),
                name: name.clone(),
                enabled: services::task_enabled(path, name),
            }),
            // Appx removal and custom operations have no value to record; the
            // former is irreversible and the latter reverts through its own op.
            Action::Appx { .. } | Action::Custom { .. } => {}
        }
    }

    entries
}

/// Writes a snapshot for a batch and returns its path, or `None` when there
/// was nothing with recordable state in it.
pub fn capture(tweaks: &[&Tweak], label: &str) -> Result<Option<PathBuf>> {
    let entries: Vec<Entry> = tweaks
        .iter()
        .flat_map(|tweak| capture_tweak(tweak))
        .collect();
    if entries.is_empty() {
        return Ok(None);
    }

    let snapshot = Snapshot {
        version: 1,
        created: Local::now().to_rfc3339(),
        computer: std::env::var("COMPUTERNAME").unwrap_or_default(),
        label: label.to_string(),
        tweak_ids: tweaks.iter().map(|tweak| tweak.id.clone()).collect(),
        entries,
    };

    let file = backup_dir()?.join(format!(
        "{}_{label}.json",
        Local::now().format("%Y%m%d_%H%M%S")
    ));
    std::fs::write(&file, serde_json::to_vec_pretty(&snapshot)?)
        .context("writing the backup file")?;

    Ok(Some(file))
}

/// Saved snapshots, newest first.
pub fn list() -> Result<Vec<BackupInfo>> {
    let dir = backup_dir()?;
    let mut found = Vec::new();

    for entry in std::fs::read_dir(&dir).context("reading the backup directory")? {
        let Ok(entry) = entry else { continue };
        let path = entry.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("json") {
            continue;
        }

        let Ok(text) = std::fs::read_to_string(&path) else {
            continue;
        };
        let Ok(snapshot) = serde_json::from_str::<Snapshot>(&text) else {
            continue;
        };

        found.push(BackupInfo {
            path: path.to_string_lossy().to_string(),
            file_name: path
                .file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .to_string(),
            created: snapshot.created,
            label: snapshot.label,
            tweak_count: snapshot.tweak_ids.len(),
            entry_count: snapshot.entries.len(),
        });
    }

    // The filename carries a sortable timestamp, so this orders by age.
    found.sort_by(|a, b| b.file_name.cmp(&a.file_name));
    Ok(found)
}

/// Replays a snapshot. Returns how many entries were restored and how many
/// failed, so a partial restore is reported honestly rather than as success.
pub fn restore(path: &Path) -> Result<(usize, usize)> {
    let text = std::fs::read_to_string(path).context("reading the backup file")?;
    let snapshot: Snapshot = serde_json::from_str(&text).context("parsing the backup file")?;

    let mut restored = 0usize;
    let mut failed = 0usize;

    for entry in &snapshot.entries {
        let outcome = match entry {
            Entry::Registry {
                path,
                name,
                existed,
                value,
                value_type,
            } => match (existed, value) {
                (true, Some(value)) => registry::write(path, name, value, *value_type),
                _ => registry::delete_value(path, name),
            },
            Entry::Service {
                name,
                existed,
                startup,
                running,
            } => {
                if *existed {
                    match startup {
                        Some(startup) => {
                            services::set_startup(name, *startup, false).and_then(|()| {
                                if *running {
                                    services::start(name)
                                } else {
                                    Ok(())
                                }
                            })
                        }
                        None => Ok(()),
                    }
                } else {
                    Ok(())
                }
            }
            Entry::ScheduledTask {
                path,
                name,
                enabled,
            } => match enabled {
                Some(enabled) => services::set_task_enabled(path, name, *enabled),
                None => Ok(()),
            },
        };

        match outcome {
            Ok(()) => restored += 1,
            Err(_) => failed += 1,
        }
    }

    Ok((restored, failed))
}
