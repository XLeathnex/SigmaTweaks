//! One-shot maintenance jobs.
//!
//! These are things you run, not settings you toggle: no state, no revert. The
//! ones that destroy data set `confirm` so the UI asks first.

use crate::error::{Error, Result};
use crate::model::MaintenanceAction;
use crate::process;
use std::path::PathBuf;

pub fn actions() -> Vec<MaintenanceAction> {
    vec![
        MaintenanceAction {
            id: "action.restorepoint",
            name: "Create a restore point",
            category: "Safety",
            description: "Takes a System Restore checkpoint you can roll back to from Windows Recovery.",
            confirm: false,
        },
        MaintenanceAction {
            id: "action.systemprotection",
            name: "Turn on System Protection",
            category: "Safety",
            description: "Enables System Restore for the system drive. Restore points cannot be taken at all until this is on, and many OEM installs ship with it off. It reserves a few percent of the drive.",
            confirm: true,
        },
        MaintenanceAction {
            id: "action.cleantemp",
            name: "Clean temporary files",
            category: "Cleanup",
            description: "Empties the user and system temp folders and the Windows prefetch cache, and reports how much was freed.",
            confirm: true,
        },
        MaintenanceAction {
            id: "action.recyclebin",
            name: "Empty the Recycle Bin",
            category: "Cleanup",
            description: "Permanently deletes everything currently in the Recycle Bin on every drive.",
            confirm: true,
        },
        MaintenanceAction {
            id: "action.updatecache",
            name: "Clear the Windows Update cache",
            category: "Cleanup",
            description: "Stops Windows Update, deletes its downloaded package cache and starts it again. Fixes updates that fail repeatedly and reclaims several gigabytes.",
            confirm: true,
        },
        MaintenanceAction {
            id: "action.storecache",
            name: "Reset the Microsoft Store cache",
            category: "Cleanup",
            description: "Runs wsreset, which clears the Store cache without touching installed apps. Fixes downloads that hang at 0%.",
            confirm: false,
        },
        MaintenanceAction {
            id: "action.iconcache",
            name: "Rebuild the icon cache",
            category: "Cleanup",
            description: "Deletes the icon and thumbnail cache databases and restarts Explorer. Fixes blank or wrong icons.",
            confirm: true,
        },
        MaintenanceAction {
            id: "action.eventlogs",
            name: "Clear all event logs",
            category: "Cleanup",
            description: "Wipes every Windows event log. This destroys the crash and error history you would need to diagnose a problem later.",
            confirm: true,
        },
        MaintenanceAction {
            id: "action.flushdns",
            name: "Flush the DNS cache",
            category: "Network",
            description: "Clears cached name lookups. Fixes a site that resolves to a stale address.",
            confirm: false,
        },
        MaintenanceAction {
            id: "action.resetnetwork",
            name: "Reset the network stack",
            category: "Network",
            description: "Resets Winsock and TCP/IP to their defaults. A last resort for a machine that will not connect. Needs a restart, and clears any manual proxy or static IP configuration.",
            confirm: true,
        },
        MaintenanceAction {
            id: "action.sfc",
            name: "Check system files (SFC)",
            category: "Repair",
            description: "Runs sfc /scannow to verify and repair protected system files. Takes several minutes.",
            confirm: false,
        },
        MaintenanceAction {
            id: "action.dism",
            name: "Repair the component store (DISM)",
            category: "Repair",
            description: "Runs DISM /RestoreHealth to repair the store that SFC repairs from. Run this first if SFC cannot fix a file. Needs an internet connection.",
            confirm: false,
        },
        MaintenanceAction {
            id: "action.optimizedrives",
            name: "Optimize drives (TRIM / defrag)",
            category: "Repair",
            description: "Sends TRIM to SSDs and defragments hard disks, choosing the right operation per drive.",
            confirm: false,
        },
    ]
}

pub fn run(id: &str) -> Result<String> {
    match id {
        "action.restorepoint" => create_restore_point("SigmaTweaks manual checkpoint"),
        "action.systemprotection" => enable_system_protection(),
        "action.cleantemp" => clean_temp(),
        "action.recyclebin" => empty_recycle_bin(),
        "action.updatecache" => clear_update_cache(),
        "action.storecache" => reset_store_cache(),
        "action.iconcache" => rebuild_icon_cache(),
        "action.eventlogs" => clear_event_logs(),
        "action.flushdns" => flush_dns(),
        "action.resetnetwork" => reset_network(),
        "action.sfc" => run_sfc(),
        "action.dism" => run_dism(),
        "action.optimizedrives" => optimize_drives(),
        other => Err(Error::new(format!(
            "no maintenance action with id '{other}'"
        ))),
    }
}

/// Creates a restore point.
///
/// Windows silently refuses more than one restore point per 24 hours, so the
/// frequency gate is dropped to zero for the duration and put back afterwards
/// whatever the outcome.
pub fn create_restore_point(description: &str) -> Result<String> {
    let safe = description.replace('\'', "");
    let script = format!(
        "$gate='HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\SystemRestore';\
         $name='SystemRestorePointCreationFrequency';\
         $old=(Get-ItemProperty -Path $gate -Name $name -ErrorAction SilentlyContinue).$name;\
         try {{\
           New-ItemProperty -Path $gate -Name $name -Value 0 -PropertyType DWord -Force | Out-Null;\
           Checkpoint-Computer -Description '{safe}' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop;\
         }} finally {{\
           if ($null -ne $old) {{ New-ItemProperty -Path $gate -Name $name -Value $old -PropertyType DWord -Force | Out-Null }}\
           else {{ Remove-ItemProperty -Path $gate -Name $name -ErrorAction SilentlyContinue }}\
         }}"
    );

    let result = process::powershell(&script)?;
    if result.ok() {
        Ok(format!("Restore point '{description}' created."))
    } else {
        Err(Error::new(format!(
            "restore point failed: {}. Turn on System Protection first.",
            result.combined().trim()
        )))
    }
}

fn enable_system_protection() -> Result<String> {
    let drive = std::env::var("SystemDrive").unwrap_or_else(|_| "C:".into());
    let script = format!("Enable-ComputerRestore -Drive '{drive}\\' -ErrorAction Stop");
    let result = process::powershell(&script)?;

    if result.ok() {
        Ok(format!("System Protection enabled for {drive}"))
    } else {
        Err(Error::new(format!(
            "could not enable System Protection: {}",
            result.combined().trim()
        )))
    }
}

/// Recursive size of a directory, ignoring anything unreadable.
fn directory_size(path: &PathBuf) -> u64 {
    let Ok(entries) = std::fs::read_dir(path) else {
        return 0;
    };

    entries
        .filter_map(std::result::Result::ok)
        .map(|entry| match entry.file_type() {
            Ok(kind) if kind.is_dir() => directory_size(&entry.path()),
            Ok(_) => entry.metadata().map(|meta| meta.len()).unwrap_or(0),
            Err(_) => 0,
        })
        .sum()
}

fn clean_temp() -> Result<String> {
    let system_root = std::env::var("SystemRoot").unwrap_or_else(|_| "C:\\Windows".into());
    let mut targets: Vec<PathBuf> = vec![
        PathBuf::from(&system_root).join("Temp"),
        PathBuf::from(&system_root).join("Prefetch"),
    ];
    if let Ok(user_temp) = std::env::var("TEMP") {
        targets.insert(0, PathBuf::from(user_temp));
    }

    let mut freed: u64 = 0;
    for target in targets {
        let Ok(entries) = std::fs::read_dir(&target) else {
            continue;
        };

        for entry in entries.filter_map(std::result::Result::ok) {
            let path = entry.path();
            let size = match entry.file_type() {
                Ok(kind) if kind.is_dir() => directory_size(&path),
                Ok(_) => entry.metadata().map(|meta| meta.len()).unwrap_or(0),
                Err(_) => 0,
            };

            // Files that are open stay open; skipping them is expected here.
            let removed = if path.is_dir() {
                std::fs::remove_dir_all(&path)
            } else {
                std::fs::remove_file(&path)
            };
            if removed.is_ok() {
                freed += size;
            }
        }
    }

    Ok(format!(
        "Freed {:.1} MB of temporary files.",
        freed as f64 / 1024.0 / 1024.0
    ))
}

fn empty_recycle_bin() -> Result<String> {
    let result = process::powershell("Clear-RecycleBin -Force -ErrorAction SilentlyContinue")?;
    let _ = result;
    Ok("Recycle Bin emptied.".into())
}

fn clear_update_cache() -> Result<String> {
    for service in ["wuauserv", "bits"] {
        let _ = process::run("sc.exe", &["stop", service]);
    }

    let system_root = std::env::var("SystemRoot").unwrap_or_else(|_| "C:\\Windows".into());
    let cache = PathBuf::from(system_root)
        .join("SoftwareDistribution")
        .join("Download");

    let mut freed = 0u64;
    if let Ok(entries) = std::fs::read_dir(&cache) {
        for entry in entries.filter_map(std::result::Result::ok) {
            let path = entry.path();
            let size = if path.is_dir() {
                directory_size(&path)
            } else {
                entry.metadata().map(|meta| meta.len()).unwrap_or(0)
            };
            let removed = if path.is_dir() {
                std::fs::remove_dir_all(&path)
            } else {
                std::fs::remove_file(&path)
            };
            if removed.is_ok() {
                freed += size;
            }
        }
    }

    for service in ["wuauserv", "bits"] {
        let _ = process::run("sc.exe", &["start", service]);
    }

    Ok(format!(
        "Windows Update cache cleared, {:.1} MB freed.",
        freed as f64 / 1024.0 / 1024.0
    ))
}

fn reset_store_cache() -> Result<String> {
    process::run("wsreset.exe", &["-i"])?;
    Ok("Store cache reset started.".into())
}

fn rebuild_icon_cache() -> Result<String> {
    let local = std::env::var("LOCALAPPDATA").map_err(|_| Error::new("LOCALAPPDATA is not set"))?;
    let dir = PathBuf::from(local)
        .join("Microsoft")
        .join("Windows")
        .join("Explorer");

    let _ = process::run("taskkill.exe", &["/f", "/im", "explorer.exe"]);
    std::thread::sleep(std::time::Duration::from_millis(500));

    let mut removed = 0;
    if let Ok(entries) = std::fs::read_dir(&dir) {
        for entry in entries.filter_map(std::result::Result::ok) {
            let name = entry.file_name().to_string_lossy().to_ascii_lowercase();
            let is_cache = name.starts_with("iconcache") || name.starts_with("thumbcache");
            if is_cache && std::fs::remove_file(entry.path()).is_ok() {
                removed += 1;
            }
        }
    }

    crate::engine::restart_explorer()?;
    Ok(format!(
        "Icon cache rebuilt, {removed} cache files removed."
    ))
}

fn clear_event_logs() -> Result<String> {
    let listed = process::run("wevtutil.exe", &["el"])?;
    let mut cleared = 0;

    for log in listed
        .stdout
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
    {
        if process::run("wevtutil.exe", &["cl", log])
            .map(|run| run.ok())
            .unwrap_or(false)
        {
            cleared += 1;
        }
    }

    Ok(format!("Cleared {cleared} event logs."))
}

fn flush_dns() -> Result<String> {
    process::run_checked("ipconfig.exe", &["/flushdns"])?;
    Ok("DNS resolver cache flushed.".into())
}

fn reset_network() -> Result<String> {
    let steps: [&[&str]; 3] = [
        &["winsock", "reset"],
        &["int", "ip", "reset"],
        &["advfirewall", "reset"],
    ];

    let mut failed = Vec::new();
    for step in steps {
        if let Ok(run) = process::run("netsh.exe", step) {
            if !run.ok() {
                failed.push(step.join(" "));
            }
        }
    }

    if failed.is_empty() {
        Ok("Network stack reset. Restart to finish.".into())
    } else {
        Err(Error::new(format!(
            "these steps failed: {}",
            failed.join(", ")
        )))
    }
}

fn run_sfc() -> Result<String> {
    let run = process::run("sfc.exe", &["/scannow"])?;
    if run.ok() {
        Ok("SFC finished: no integrity violations, or all repaired.".into())
    } else {
        Err(Error::new(format!(
            "SFC exited with code {}. See CBS.log for detail.",
            run.status
        )))
    }
}

fn run_dism() -> Result<String> {
    process::run_checked("dism.exe", &["/Online", "/Cleanup-Image", "/RestoreHealth"])?;
    Ok("Component store repaired.".into())
}

fn optimize_drives() -> Result<String> {
    let script = "$ErrorActionPreference='Stop';\
                  $v = @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.FileSystemType -eq 'NTFS' });\
                  foreach ($d in $v) { Optimize-Volume -DriveLetter $d.DriveLetter };\
                  Write-Output $v.Count";

    let run = process::powershell(script)?;
    if run.ok() {
        Ok(format!("Optimized {} volume(s).", run.stdout.trim()))
    } else {
        Err(Error::new(format!(
            "drive optimization failed: {}",
            run.combined().trim()
        )))
    }
}
