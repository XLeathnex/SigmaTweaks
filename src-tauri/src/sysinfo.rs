//! Facts about the machine, used for the overview page and for deciding which
//! tweaks apply here at all.

use crate::error::Result;
use crate::model::RegValue;
use crate::process;
use crate::registry;
use serde::Serialize;
use std::sync::OnceLock;

const CURRENT_VERSION: &str = "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion";

#[derive(Debug, Clone, Serialize)]
pub struct SystemInfo {
    pub computer_name: String,
    pub user_name: String,
    pub os_name: String,
    pub display_version: String,
    pub edition: String,
    pub build: u32,
    pub is_windows11: bool,
    pub cpu: String,
    pub logical_processors: usize,
    pub memory_gb: f64,
    pub gpu: String,
    pub system_drive: String,
    pub free_space_gb: f64,
    pub is_admin: bool,
    /// `None` when the media type could not be determined.
    pub is_ssd: Option<bool>,
    pub app_version: &'static str,
}

fn read_text(path: &str, name: &str) -> Option<String> {
    match registry::read(path, name) {
        Ok(Some(RegValue::Text(value))) => Some(value),
        Ok(Some(RegValue::Int(value))) => Some(value.to_string()),
        _ => None,
    }
}

fn env(name: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| "unknown".into())
}

pub fn build_number() -> u32 {
    read_text(CURRENT_VERSION, "CurrentBuildNumber")
        .and_then(|text| text.trim().parse().ok())
        .unwrap_or(0)
}

/// Windows 11 still reports itself as 10.0; the build number is what
/// distinguishes it, and 22000 is the first one.
pub fn is_windows11() -> bool {
    build_number() >= 22000
}

/// Whether the system disk is solid state.
///
/// Cached: the answer cannot change while the app is running, and the query
/// costs a PowerShell launch. `None` means the media type is genuinely
/// unknown, which is treated as "do not block SSD-only tweaks".
pub fn is_ssd() -> Option<bool> {
    static CACHE: OnceLock<Option<bool>> = OnceLock::new();
    *CACHE.get_or_init(|| {
        let script = "$ErrorActionPreference='SilentlyContinue';\
                      (Get-PhysicalDisk | Select-Object -ExpandProperty MediaType) -join ','";
        let run = process::powershell(script).ok()?;
        let text = run.stdout.to_ascii_uppercase();
        if text.contains("SSD") {
            Some(true)
        } else if text.contains("HDD") {
            Some(false)
        } else {
            None
        }
    })
}

fn memory_gb() -> f64 {
    use windows::Win32::System::SystemInformation::{GlobalMemoryStatusEx, MEMORYSTATUSEX};

    let mut status = MEMORYSTATUSEX {
        dwLength: std::mem::size_of::<MEMORYSTATUSEX>() as u32,
        ..Default::default()
    };

    // SAFETY: dwLength is set to the size of the struct we pass, which is the
    // only precondition GlobalMemoryStatusEx has.
    let ok = unsafe { GlobalMemoryStatusEx(&mut status) }.is_ok();
    if !ok {
        return 0.0;
    }

    round1(status.ullTotalPhys as f64 / 1024.0 / 1024.0 / 1024.0)
}

fn free_space_gb(drive: &str) -> f64 {
    use windows::core::HSTRING;
    use windows::Win32::Storage::FileSystem::GetDiskFreeSpaceExW;

    let root = HSTRING::from(format!("{drive}\\"));
    let mut free: u64 = 0;

    // SAFETY: `root` outlives the call and the out-pointers are valid locals.
    let ok = unsafe { GetDiskFreeSpaceExW(&root, None, None, Some(&mut free)) }.is_ok();
    if !ok {
        return 0.0;
    }

    round1(free as f64 / 1024.0 / 1024.0 / 1024.0)
}

fn round1(value: f64) -> f64 {
    (value * 10.0).round() / 10.0
}

fn gpu_name() -> String {
    // The display adapter class key; 0000 is the primary adapter.
    let class = "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Class\\{4d36e968-e325-11ce-bfc1-08002be10318}\\0000";
    read_text(class, "DriverDesc").unwrap_or_else(|| "Unknown".into())
}

fn cpu_name() -> String {
    read_text(
        "HKLM:\\HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
        "ProcessorNameString",
    )
    .map(|name| name.trim().to_string())
    .unwrap_or_else(|| "Unknown".into())
}

/// The subset of the host the applicability rules care about.
pub fn facts() -> crate::model::HostFacts {
    let build = build_number();
    crate::model::HostFacts {
        build,
        is_windows11: build >= 22000,
        is_ssd: is_ssd(),
    }
}

pub fn collect() -> Result<SystemInfo> {
    let build = build_number();
    let system_drive = std::env::var("SystemDrive").unwrap_or_else(|_| "C:".into());

    Ok(SystemInfo {
        computer_name: env("COMPUTERNAME"),
        user_name: env("USERNAME"),
        os_name: read_text(CURRENT_VERSION, "ProductName").unwrap_or_else(|| "Windows".into()),
        display_version: read_text(CURRENT_VERSION, "DisplayVersion").unwrap_or_default(),
        edition: read_text(CURRENT_VERSION, "EditionID").unwrap_or_default(),
        build,
        is_windows11: build >= 22000,
        cpu: cpu_name(),
        logical_processors: std::thread::available_parallelism()
            .map(|count| count.get())
            .unwrap_or(0),
        memory_gb: memory_gb(),
        gpu: gpu_name(),
        free_space_gb: free_space_gb(&system_drive),
        system_drive,
        is_admin: crate::elevate::is_elevated(),
        is_ssd: is_ssd(),
        app_version: env!("CARGO_PKG_VERSION"),
    })
}
