fn main() {
    // build.rs is compiled for the host, so the target OS has to come from
    // Cargo's environment rather than a cfg! check. On a non-Windows host
    // building for tests there is no Tauri context to generate.
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    if target_os == "windows" {
        tauri_build::build();
    }
}
