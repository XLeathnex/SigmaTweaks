//! The changes that cannot be expressed as "write this value there".
//!
//! Each [`CustomOp`] implements apply, revert and state detection. Where the
//! change has to go through a Windows tool (powercfg, fsutil, DISM) the state
//! is still read back from the registry wherever possible, because parsing
//! localised console output is not something to build a UI on.

use crate::error::{Error, Result};
use crate::model::{CustomOp, RegValue, State, ValueType};
use crate::process;
use crate::registry;

const TCPIP_INTERFACES: &str =
    "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters\\Interfaces";
const NETBT_INTERFACES: &str =
    "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\NetBT\\Parameters\\Interfaces";
const CONTEXT_MENU_CLSID: &str =
    "HKCU:\\Software\\Classes\\CLSID\\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}";
const SIGMA_KEY: &str = "HKCU:\\Software\\SigmaTweaks";

/// The hidden Ultimate Performance scheme Windows ships as a template.
const ULTIMATE_TEMPLATE: &str = "e9a42b02-d5df-448d-aa00-03f14749eb61";
/// The stock Balanced scheme, which revert goes back to.
const BALANCED_SCHEME: &str = "381b4222-f694-41f0-9685-ff5bb260df2e";
/// powercfg subgroup and setting GUIDs.
const USB_SUBGROUP: &str = "2a737441-1930-4402-8d77-b2bebba308a3";
const USB_SELECTIVE_SUSPEND: &str = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226";
const SLEEP_SUBGROUP: &str = "238c9fa8-0aad-41ed-83f4-97be242c8f20";
const SLEEP_AFTER: &str = "29f6c1db-86da-48c5-9fdb-f2b67b1f44da";

pub fn apply(op: CustomOp) -> Result<()> {
    match op {
        CustomOp::NumLock => set_num_lock("2"),
        CustomOp::ClassicContextMenu => registry::write(
            &format!("{CONTEXT_MENU_CLSID}\\InprocServer32"),
            "",
            // An empty default value tells the shell that no handler implements
            // the compact menu, so it falls back to the Windows 10 one.
            &RegValue::Text(String::new()),
            ValueType::String,
        ),
        CustomOp::Nagle => set_nagle(true),
        CustomOp::Netbios => set_netbios(true),
        CustomOp::CloudflareDns => set_dns(Some(("1.1.1.1", "1.0.0.1"))),
        CustomOp::NtfsLastAccess => set_last_access(true),
        CustomOp::Hibernation => power_hibernate(false),
        CustomOp::ReservedStorage => set_reserved_storage(false),
        CustomOp::UltimatePerformance => enable_ultimate_performance(),
        CustomOp::UsbSelectiveSuspend => set_usb_suspend(false),
        CustomOp::NeverSleepAc => set_sleep_ac(0, 0),
    }
}

pub fn revert(op: CustomOp) -> Result<()> {
    match op {
        // 0x80000000 is the stock value: "NumLock follows the previous session".
        CustomOp::NumLock => set_num_lock("2147483648"),
        CustomOp::ClassicContextMenu => registry::delete_key(CONTEXT_MENU_CLSID),
        CustomOp::Nagle => set_nagle(false),
        CustomOp::Netbios => set_netbios(false),
        CustomOp::CloudflareDns => set_dns(None),
        CustomOp::NtfsLastAccess => set_last_access(false),
        CustomOp::Hibernation => power_hibernate(true),
        CustomOp::ReservedStorage => set_reserved_storage(true),
        CustomOp::UltimatePerformance => {
            process::run_checked("powercfg.exe", &["/setactive", BALANCED_SCHEME])?;
            let _ = registry::delete_value(SIGMA_KEY, "UltimatePerformanceScheme");
            Ok(())
        }
        CustomOp::UsbSelectiveSuspend => set_usb_suspend(true),
        // Windows ships 30 minutes to sleep and 180 to hibernate on AC.
        CustomOp::NeverSleepAc => set_sleep_ac(30, 180),
    }
}

pub fn state(op: CustomOp) -> State {
    match op {
        CustomOp::NumLock => match registry::read(
            "HKCU:\\Control Panel\\Keyboard",
            "InitialKeyboardIndicators",
        ) {
            Ok(Some(RegValue::Text(value))) if value.trim() == "2" => State::Applied,
            Ok(Some(_)) => State::NotApplied,
            _ => State::Unknown,
        },
        CustomOp::ClassicContextMenu => {
            match registry::read(&format!("{CONTEXT_MENU_CLSID}\\InprocServer32"), "") {
                Ok(Some(_)) => State::Applied,
                _ => State::NotApplied,
            }
        }
        CustomOp::Nagle => interface_state(TCPIP_INTERFACES, |path| {
            registry::matches(path, "TcpAckFrequency", Some(&RegValue::Int(1)))
                && registry::matches(path, "TCPNoDelay", Some(&RegValue::Int(1)))
        }),
        CustomOp::Netbios => interface_state(NETBT_INTERFACES, |path| {
            registry::matches(path, "NetbiosOptions", Some(&RegValue::Int(2)))
        }),
        CustomOp::CloudflareDns => dns_state(),
        CustomOp::NtfsLastAccess => {
            match registry::read(
                "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\FileSystem",
                "NtfsDisableLastAccessUpdate",
            ) {
                // Bit 0 carries the setting; bit 31 only records "system managed".
                Ok(Some(RegValue::Int(value))) if value & 1 == 1 => State::Applied,
                Ok(Some(_)) => State::NotApplied,
                _ => State::Unknown,
            }
        }
        CustomOp::Hibernation => {
            match registry::read(
                "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Power",
                "HibernateEnabled",
            ) {
                Ok(Some(RegValue::Int(0))) => State::Applied,
                Ok(Some(_)) => State::NotApplied,
                _ => State::Unknown,
            }
        }
        CustomOp::ReservedStorage => match process::run(
            "dism.exe",
            &["/Online", "/English", "/Get-ReservedStorageState"],
        ) {
            Ok(run) if run.ok() => {
                let text = run.stdout.to_ascii_lowercase();
                if text.contains("disabled") {
                    State::Applied
                } else if text.contains("enabled") {
                    State::NotApplied
                } else {
                    State::Unknown
                }
            }
            _ => State::Unknown,
        },
        CustomOp::UltimatePerformance => ultimate_performance_state(),
        CustomOp::UsbSelectiveSuspend => {
            match power_setting_is_zero(USB_SUBGROUP, USB_SELECTIVE_SUSPEND) {
                Some(true) => State::Applied,
                Some(false) => State::NotApplied,
                None => State::Unknown,
            }
        }
        CustomOp::NeverSleepAc => match power_setting_is_zero(SLEEP_SUBGROUP, SLEEP_AFTER) {
            Some(true) => State::Applied,
            Some(false) => State::NotApplied,
            None => State::Unknown,
        },
    }
}

fn set_num_lock(value: &str) -> Result<()> {
    let text = RegValue::Text(value.to_string());
    registry::write(
        "HKCU:\\Control Panel\\Keyboard",
        "InitialKeyboardIndicators",
        &text,
        ValueType::String,
    )?;
    // The .DEFAULT profile is what the sign-in screen itself uses.
    registry::write(
        "HKU:\\.DEFAULT\\Control Panel\\Keyboard",
        "InitialKeyboardIndicators",
        &text,
        ValueType::String,
    )
}

/// Interfaces that actually hold an address, which are the only ones worth
/// reconfiguring. Tunnels and disconnected adapters are skipped.
fn configured_interfaces(root: &str, require_address: bool) -> Result<Vec<String>> {
    let mut found = Vec::new();
    for name in registry::subkeys(root)? {
        let path = format!("{root}\\{name}");
        if require_address {
            let has_address = registry::read(&path, "DhcpIPAddress")?.is_some()
                || registry::read(&path, "IPAddress")?.is_some();
            if !has_address {
                continue;
            }
        }
        found.push(path);
    }
    Ok(found)
}

fn interface_state(root: &str, test: impl Fn(&str) -> bool) -> State {
    let Ok(interfaces) = configured_interfaces(root, root == TCPIP_INTERFACES) else {
        return State::Unknown;
    };
    if interfaces.is_empty() {
        return State::Unknown;
    }

    let hits = interfaces.iter().filter(|path| test(path)).count();
    if hits == 0 {
        State::NotApplied
    } else if hits == interfaces.len() {
        State::Applied
    } else {
        State::Partial
    }
}

fn set_nagle(disable: bool) -> Result<()> {
    let interfaces = configured_interfaces(TCPIP_INTERFACES, true)?;
    if interfaces.is_empty() {
        return Err(Error::new("no configured network interfaces were found"));
    }

    for path in interfaces {
        if disable {
            registry::write(
                &path,
                "TcpAckFrequency",
                &RegValue::Int(1),
                ValueType::Dword,
            )?;
            registry::write(&path, "TCPNoDelay", &RegValue::Int(1), ValueType::Dword)?;
        } else {
            registry::delete_value(&path, "TcpAckFrequency")?;
            registry::delete_value(&path, "TCPNoDelay")?;
        }
    }
    Ok(())
}

fn set_netbios(disable: bool) -> Result<()> {
    let interfaces = configured_interfaces(NETBT_INTERFACES, false)?;
    if interfaces.is_empty() {
        return Err(Error::new("no NetBT interfaces were found"));
    }

    // 2 = disable NetBIOS over TCP/IP, 0 = use the DHCP server's setting.
    let value = RegValue::Int(if disable { 2 } else { 0 });
    for path in interfaces {
        registry::write(&path, "NetbiosOptions", &value, ValueType::Dword)?;
    }
    Ok(())
}

fn set_dns(servers: Option<(&str, &str)>) -> Result<()> {
    let script = match servers {
        Some((primary, secondary)) => format!(
            "$ErrorActionPreference='Stop';\
             $a = @(Get-NetAdapter -Physical | Where-Object Status -eq 'Up');\
             if (-not $a) {{ Write-Error 'no connected adapters' }}\
             foreach ($n in $a) {{ Set-DnsClientServerAddress -InterfaceIndex $n.ifIndex -ServerAddresses @('{primary}','{secondary}') }}\
             Clear-DnsClientCache"
        ),
        None => "$ErrorActionPreference='Stop';\
             foreach ($n in @(Get-NetAdapter -Physical | Where-Object Status -eq 'Up')) \
             { Set-DnsClientServerAddress -InterfaceIndex $n.ifIndex -ResetServerAddresses }\
             Clear-DnsClientCache"
            .to_string(),
    };

    let result = process::powershell(&script)?;
    if result.ok() {
        Ok(())
    } else {
        Err(Error::new(format!(
            "setting DNS: {}",
            result.combined().trim()
        )))
    }
}

fn dns_state() -> State {
    // NameServer is the statically configured list; DHCP-supplied servers live
    // under DhcpNameServer and are correctly reported as "not applied".
    let Ok(interfaces) = configured_interfaces(TCPIP_INTERFACES, true) else {
        return State::Unknown;
    };
    if interfaces.is_empty() {
        return State::Unknown;
    }

    let hits = interfaces
        .iter()
        .filter(|path| {
            matches!(
                registry::read(path, "NameServer"),
                Ok(Some(RegValue::Text(ref value))) if value.contains("1.1.1.1")
            )
        })
        .count();

    if hits == 0 {
        State::NotApplied
    } else if hits == interfaces.len() {
        State::Applied
    } else {
        State::Partial
    }
}

fn set_last_access(disable: bool) -> Result<()> {
    // 1 = user disabled, 2 = system managed (the Windows default).
    let flag = if disable { "1" } else { "2" };
    process::run_checked(
        "fsutil.exe",
        &["behavior", "set", "disablelastaccess", flag],
    )?;
    Ok(())
}

fn power_hibernate(on: bool) -> Result<()> {
    process::run_checked(
        "powercfg.exe",
        &["/hibernate", if on { "on" } else { "off" }],
    )?;
    Ok(())
}

fn set_reserved_storage(enabled: bool) -> Result<()> {
    let state = if enabled {
        "/State:Enabled"
    } else {
        "/State:Disabled"
    };
    process::run_checked(
        "dism.exe",
        &["/Online", "/English", "/Set-ReservedStorageState", state],
    )?;
    Ok(())
}

/// Duplicates the hidden Ultimate Performance template and activates it.
///
/// The duplicate gets a fresh GUID, so it is recorded under our own key: that
/// makes the state check exact instead of matching a localised scheme name.
fn enable_ultimate_performance() -> Result<()> {
    let duplicate = process::run("powercfg.exe", &["-duplicatescheme", ULTIMATE_TEMPLATE])?;
    let scheme = extract_guid(&duplicate.combined())
        .or_else(|| {
            // Already duplicated by an earlier run: find it in the scheme list.
            process::run("powercfg.exe", &["/list"])
                .ok()
                .and_then(|listed| {
                    listed
                        .stdout
                        .lines()
                        .find(|line| line.contains("Ultimate"))
                        .and_then(extract_guid)
                })
        })
        .ok_or_else(|| {
            Error::new("the Ultimate Performance plan is not available on this system")
        })?;

    process::run_checked("powercfg.exe", &["/setactive", &scheme])?;
    registry::write(
        SIGMA_KEY,
        "UltimatePerformanceScheme",
        &RegValue::Text(scheme),
        ValueType::String,
    )
}

fn ultimate_performance_state() -> State {
    let Some(active) = active_scheme() else {
        return State::Unknown;
    };

    match registry::read(SIGMA_KEY, "UltimatePerformanceScheme") {
        Ok(Some(RegValue::Text(recorded))) => {
            if recorded.eq_ignore_ascii_case(&active) {
                State::Applied
            } else {
                State::NotApplied
            }
        }
        // Never applied through SigmaTweaks: fall back to the scheme name,
        // which is only reliable on an English install.
        _ => match process::run("powercfg.exe", &["/getactivescheme"]) {
            Ok(run) if run.stdout.contains("Ultimate") => State::Applied,
            Ok(_) => State::NotApplied,
            Err(_) => State::Unknown,
        },
    }
}

fn active_scheme() -> Option<String> {
    let run = process::run("powercfg.exe", &["/getactivescheme"]).ok()?;
    extract_guid(&run.stdout)
}

/// Pulls the first GUID out of powercfg output, which is the only part of it
/// that is not localised.
fn extract_guid(text: &str) -> Option<String> {
    let bytes: Vec<char> = text.chars().collect();
    let is_hex = |c: char| c.is_ascii_hexdigit();

    for start in 0..bytes.len().saturating_sub(35) {
        let window = &bytes[start..start + 36];
        let shaped = window.iter().enumerate().all(|(index, c)| match index {
            8 | 13 | 18 | 23 => *c == '-',
            _ => is_hex(*c),
        });
        if shaped {
            return Some(window.iter().collect::<String>().to_ascii_lowercase());
        }
    }
    None
}

fn set_usb_suspend(enabled: bool) -> Result<()> {
    let value = if enabled { "1" } else { "0" };
    for verb in ["/setacvalueindex", "/setdcvalueindex"] {
        process::run_checked(
            "powercfg.exe",
            &[
                verb,
                "SCHEME_CURRENT",
                USB_SUBGROUP,
                USB_SELECTIVE_SUSPEND,
                value,
            ],
        )?;
    }
    process::run_checked("powercfg.exe", &["/setactive", "SCHEME_CURRENT"])?;
    Ok(())
}

fn set_sleep_ac(standby_minutes: u32, hibernate_minutes: u32) -> Result<()> {
    process::run_checked(
        "powercfg.exe",
        &[
            "/change",
            "standby-timeout-ac",
            &standby_minutes.to_string(),
        ],
    )?;
    process::run_checked(
        "powercfg.exe",
        &[
            "/change",
            "hibernate-timeout-ac",
            &hibernate_minutes.to_string(),
        ],
    )?;
    Ok(())
}

/// Whether a power setting's AC index is zero, which powercfg prints as a hex
/// word. `None` when the setting could not be read.
fn power_setting_is_zero(subgroup: &str, setting: &str) -> Option<bool> {
    let run = process::run(
        "powercfg.exe",
        &["/query", "SCHEME_CURRENT", subgroup, setting],
    )
    .ok()?;
    if !run.ok() {
        return None;
    }

    let line = run
        .stdout
        .lines()
        .find(|line| line.contains("AC Power Setting Index"))?;
    let index = line.rsplit(':').next()?.trim().to_ascii_lowercase();
    let numeric = index.trim_start_matches("0x");
    Some(u64::from_str_radix(numeric, 16).ok()? == 0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_the_guid_in_powercfg_output() {
        let sample = "Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)";
        assert_eq!(
            extract_guid(sample).as_deref(),
            Some("381b4222-f694-41f0-9685-ff5bb260df2e")
        );
    }

    #[test]
    fn reports_no_guid_when_there_is_none() {
        assert_eq!(extract_guid("Ultimate Performance not available"), None);
    }

    #[test]
    fn accepts_uppercase_guids() {
        let sample = "GUID: E9A42B02-D5DF-448D-AA00-03F14749EB61";
        assert_eq!(
            extract_guid(sample).as_deref(),
            Some("e9a42b02-d5df-448d-aa00-03f14749eb61")
        );
    }
}
