//! SigmaTweaks: a Windows 11 optimization, privacy and debloat tool.
//!
//! The catalog in `resources/catalog.json` is the single source of truth for
//! what a tweak changes. [`engine`] derives apply, revert and state detection
//! from it, [`backup`] records what was there first, and [`commands`] exposes
//! the result to the interface.
//!
//! Two rules hold throughout and are enforced by tests in [`catalog`]:
//! nothing here disables Defender, SmartScreen, UAC or the firewall, and the
//! services and packages the system depends on are on the protected lists in
//! [`protected`], which reject changes even when a catalog entry asks for them.
//!
//! The application only runs on Windows, but the catalog, its validation rules
//! and the registry value codec are deliberately free of Windows bindings so
//! that `cargo test` exercises them on any host.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

pub mod catalog;
pub mod codec;
pub mod error;
pub mod model;
pub mod parse;
pub mod protected;

#[cfg(windows)]
pub mod appx;
#[cfg(windows)]
pub mod backup;
#[cfg(windows)]
pub mod commands;
#[cfg(windows)]
pub mod custom;
#[cfg(windows)]
pub mod elevate;
#[cfg(windows)]
pub mod engine;
#[cfg(windows)]
pub mod inventory;
#[cfg(windows)]
pub mod maintenance;
#[cfg(windows)]
pub mod process;
#[cfg(windows)]
pub mod registry;
#[cfg(windows)]
pub mod services;
#[cfg(windows)]
pub mod sysinfo;

#[cfg(windows)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            commands::get_system_info,
            commands::get_catalog,
            commands::warm_inventory,
            commands::get_states,
            commands::run_batch,
            commands::run_maintenance,
            commands::list_backups,
            commands::restore_backup,
            commands::export_profile,
            commands::relaunch_elevated,
            commands::open_data_directory,
            commands::restart_windows,
        ])
        .run(tauri::generate_context!())
        .expect("SigmaTweaks failed to start");
}

#[cfg(not(windows))]
pub fn run() {
    eprintln!("SigmaTweaks only runs on Windows.");
    std::process::exit(1);
}
