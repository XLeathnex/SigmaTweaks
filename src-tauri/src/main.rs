// Hides the console window in release builds; debug builds keep it so panics
// and log output stay visible.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    sigmatweaks_lib::run();
}
