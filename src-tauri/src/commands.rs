//! The bridge between the webview and the backend.
//!
//! Long-running work is pushed onto a blocking thread so the window keeps
//! painting, and progress is streamed back as `sigma://log` events rather than
//! being batched up and delivered at the end.

use crate::backup::{self, BackupInfo};
use crate::catalog;
use crate::engine;
use crate::error::{Error, Result};
use crate::maintenance;
use crate::model::{MaintenanceAction, Mode, Preset, State, Tweak, TweakResult, TweakStatus};
use crate::sysinfo::{self, SystemInfo};
use serde::Serialize;
use tauri::{AppHandle, Emitter};

#[derive(Debug, Clone, Serialize)]
pub struct LogLine {
    pub level: &'static str,
    pub message: String,
}

fn log(app: &AppHandle, level: &'static str, message: impl Into<String>) {
    let line = LogLine {
        level,
        message: message.into(),
    };
    // A failed emit means the window is closing; the work still finishes.
    let _ = app.emit("sigma://log", line);
}

#[derive(Debug, Clone, Serialize)]
pub struct CatalogPayload {
    pub tweaks: &'static [Tweak],
    pub presets: &'static [Preset],
    pub categories: Vec<&'static str>,
    pub actions: Vec<MaintenanceAction>,
}

#[derive(Debug, Clone, Serialize)]
pub struct BatchOutcome {
    pub results: Vec<TweakResult>,
    pub succeeded: usize,
    pub failed: usize,
    pub backup: Option<String>,
    pub restart_required: bool,
}

#[tauri::command]
pub fn get_system_info() -> Result<SystemInfo> {
    sysinfo::collect()
}

/// Builds the package and scheduled-task snapshots ahead of the first scan, so
/// the user is not waiting on them when the window opens.
#[tauri::command]
pub async fn warm_inventory() -> Result<()> {
    tauri::async_runtime::spawn_blocking(crate::inventory::warm)
        .await
        .map_err(|err| Error::new(format!("inventory scan did not finish: {err}")))?
}

#[tauri::command]
pub fn get_catalog() -> CatalogPayload {
    CatalogPayload {
        tweaks: catalog::tweaks(),
        presets: catalog::presets(),
        categories: catalog::categories(),
        actions: maintenance::actions(),
    }
}

/// Current state for the given ids, or the whole catalog when none are given.
///
/// Scanning everything is the normal case: the most useful thing this app can
/// report is what was already done to the machine before it arrived, and that
/// only reads well if every category shows its count at once. Store packages
/// and scheduled tasks come from a cached snapshot ([`crate::inventory`]) so
/// the whole catalog costs two process launches rather than one per item.
#[tauri::command]
pub async fn get_states(ids: Option<Vec<String>>) -> Result<Vec<TweakStatus>> {
    tauri::async_runtime::spawn_blocking(move || {
        let wanted: Vec<&'static Tweak> = match &ids {
            Some(ids) => catalog::resolve(ids),
            None => catalog::tweaks().iter().collect(),
        };
        let facts = sysinfo::facts();

        wanted
            .into_iter()
            .map(
                |tweak| match catalog::not_applicable_reason(tweak, &facts) {
                    Some(reason) => TweakStatus {
                        id: tweak.id.clone(),
                        state: State::NotApplicable,
                        reason: Some(reason),
                        matched: 0,
                        total: 0,
                    },
                    None => engine::inspect(tweak),
                },
            )
            .collect()
    })
    .await
    .map_err(|err| Error::new(format!("state check did not finish: {err}")))
}

#[tauri::command]
pub async fn run_batch(
    app: AppHandle,
    ids: Vec<String>,
    mode: Mode,
    create_restore_point: bool,
) -> Result<BatchOutcome> {
    tauri::async_runtime::spawn_blocking(move || {
        let selected = catalog::resolve(&ids);
        if selected.is_empty() {
            return Err(Error::new("none of the selected ids matched a tweak"));
        }

        // A preset selects across the whole catalog, so the batch routinely
        // contains tweaks this machine cannot use. Drop them with a note
        // rather than letting them fail one by one.
        let facts = sysinfo::facts();
        let mut tweaks = Vec::with_capacity(selected.len());
        for tweak in selected {
            match catalog::not_applicable_reason(tweak, &facts) {
                Some(reason) => log(&app, "info", format!("Skipping {}: {reason}.", tweak.id)),
                None => tweaks.push(tweak),
            }
        }

        if tweaks.is_empty() {
            log(
                &app,
                "warn",
                "Nothing in that selection applies to this machine.",
            );
            return Ok(BatchOutcome {
                results: Vec::new(),
                succeeded: 0,
                failed: 0,
                backup: None,
                restart_required: false,
            });
        }

        let verb = match mode {
            Mode::Apply => "Applying",
            Mode::Revert => "Reverting",
        };
        log(&app, "info", format!("{verb} {} tweak(s)...", tweaks.len()));

        if create_restore_point {
            log(
                &app,
                "info",
                "Creating a restore point (this can take a minute)...",
            );
            match maintenance::create_restore_point("SigmaTweaks") {
                Ok(message) => log(&app, "success", message),
                // A missing restore point is worth knowing about but is not a
                // reason to refuse work the user explicitly asked for.
                Err(err) => log(&app, "warn", err.to_string()),
            }
        }

        let label = match mode {
            Mode::Apply => "apply",
            Mode::Revert => "revert",
        };
        let backup = match backup::capture(&tweaks, label) {
            Ok(Some(path)) => {
                let name = path
                    .file_name()
                    .map(|name| name.to_string_lossy().to_string())
                    .unwrap_or_default();
                log(&app, "info", format!("Previous state saved to {name}"));
                Some(path.to_string_lossy().to_string())
            }
            Ok(None) => None,
            Err(err) => {
                log(&app, "warn", format!("Could not write a backup: {err}"));
                None
            }
        };

        let elevated = crate::elevate::is_elevated();
        let mut results = Vec::with_capacity(tweaks.len());
        let mut restart_required = false;
        let mut restart_explorer = false;

        for tweak in &tweaks {
            let result = engine::run(tweak, mode, elevated);

            if result.success {
                log(&app, "success", format!("  {}", tweak.name));
                if tweak.requires_restart {
                    restart_required = true;
                }
                if tweak.restart_explorer {
                    restart_explorer = true;
                }
            } else {
                log(
                    &app,
                    "error",
                    format!("  {} - {}", tweak.name, result.message),
                );
            }

            results.push(result);
        }

        // Packages and tasks may have changed, so the next scan must re-read
        // them rather than trusting the snapshot taken before this batch.
        crate::inventory::invalidate();

        if restart_explorer {
            log(&app, "info", "Restarting Explorer...");
            let _ = engine::restart_explorer();
        }

        let succeeded = results.iter().filter(|result| result.success).count();
        let failed = results.len() - succeeded;

        log(
            &app,
            if failed > 0 { "warn" } else { "success" },
            format!("Finished: {succeeded} succeeded, {failed} failed."),
        );
        if restart_required {
            log(
                &app,
                "warn",
                "Some changes only take effect after a restart.",
            );
        }

        Ok(BatchOutcome {
            results,
            succeeded,
            failed,
            backup,
            restart_required,
        })
    })
    .await
    .map_err(|err| Error::new(format!("the batch did not finish: {err}")))?
}

#[tauri::command]
pub async fn run_maintenance(app: AppHandle, id: String) -> Result<String> {
    tauri::async_runtime::spawn_blocking(move || {
        let name = maintenance::actions()
            .into_iter()
            .find(|action| action.id == id)
            .map(|action| action.name)
            .unwrap_or("action");

        log(&app, "info", format!("Running: {name}"));
        match maintenance::run(&id) {
            Ok(message) => {
                log(&app, "success", message.clone());
                Ok(message)
            }
            Err(err) => {
                log(&app, "error", format!("{name} failed: {err}"));
                Err(err)
            }
        }
    })
    .await
    .map_err(|err| Error::new(format!("the action did not finish: {err}")))?
}

#[tauri::command]
pub fn list_backups() -> Result<Vec<BackupInfo>> {
    backup::list()
}

#[tauri::command]
pub async fn restore_backup(app: AppHandle, path: String) -> Result<String> {
    tauri::async_runtime::spawn_blocking(move || {
        log(&app, "info", "Restoring backup...");
        let (restored, failed) = backup::restore(std::path::Path::new(&path))?;

        let message = format!("Restored {restored} recorded values, {failed} failed.");
        log(
            &app,
            if failed > 0 { "warn" } else { "success" },
            message.clone(),
        );
        Ok(message)
    })
    .await
    .map_err(|err| Error::new(format!("the restore did not finish: {err}")))?
}

/// Ids of every tweak currently applied, for saving as a profile.
#[tauri::command]
pub async fn export_profile() -> Result<String> {
    tauri::async_runtime::spawn_blocking(|| {
        let facts = sysinfo::facts();
        let applied: Vec<String> = catalog::tweaks()
            .iter()
            .filter(|tweak| catalog::not_applicable_reason(tweak, &facts).is_none())
            .filter(|tweak| engine::state(tweak) == State::Applied)
            .map(|tweak| tweak.id.clone())
            .collect();

        let profile = serde_json::json!({
            "name": "Exported profile",
            "description": format!("Captured from {}", std::env::var("COMPUTERNAME").unwrap_or_default()),
            "tweaks": applied,
        });

        let dir = backup::data_dir()?.join("profiles");
        std::fs::create_dir_all(&dir)?;
        let file = dir.join(format!(
            "profile_{}.json",
            chrono::Local::now().format("%Y%m%d_%H%M%S")
        ));
        std::fs::write(&file, serde_json::to_vec_pretty(&profile)?)?;

        Ok(file.to_string_lossy().to_string())
    })
    .await
    .map_err(|err| Error::new(format!("the export did not finish: {err}")))?
}

#[tauri::command]
pub fn relaunch_elevated(app: AppHandle) -> Result<()> {
    crate::elevate::relaunch_as_admin()?;
    app.exit(0);
    Ok(())
}

/// Opens the logs, backups and profiles folder in Explorer.
#[tauri::command]
pub fn open_data_directory() -> Result<String> {
    let dir = backup::data_dir()?;
    let path = dir.to_string_lossy().to_string();
    // explorer.exe returns a non-zero code even when it succeeds, so the
    // result is deliberately not checked.
    let _ = crate::process::run("explorer.exe", &[&path]);
    Ok(path)
}

#[tauri::command]
pub fn restart_windows() -> Result<()> {
    crate::process::run_checked(
        "shutdown.exe",
        &["/r", "/t", "15", "/c", "Restart requested by SigmaTweaks"],
    )?;
    Ok(())
}
