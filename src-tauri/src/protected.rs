//! The two lists SigmaTweaks will not cross.
//!
//! These live in their own platform-independent module so that the catalog
//! tests can assert against them: a tweak that ever starts targeting one of
//! these fails the build rather than shipping.

/// Services SigmaTweaks refuses to reconfigure.
///
/// Losing any of these breaks networking, logon, updates or security in ways a
/// revert cannot reliably undo, so they are rejected even when a catalog entry
/// asks for them.
pub const SERVICES: &[&str] = &[
    "BFE",
    "Dhcp",
    "Dnscache",
    "EventLog",
    "gpsvc",
    "LanmanWorkstation",
    "mpssvc",
    "NlaSvc",
    "nsi",
    "PlugPlay",
    "Power",
    "ProfSvc",
    "RpcEptMapper",
    "RpcSs",
    "SamSs",
    "Schedule",
    "SecurityHealthService",
    "Sense",
    "TrustedInstaller",
    "UserManager",
    "WdNisSvc",
    "WinDefend",
    "Winmgmt",
    "wscsvc",
    "wuauserv",
];

/// Store packages that are never offered for removal.
///
/// Removing any of these breaks the shell, the Store, app installation or the
/// Windows Security UI, and none of them can be reinstalled from inside the
/// system they just broke.
pub const PACKAGES: &[&str] = &[
    "Microsoft.DesktopAppInstaller",
    "Microsoft.HEIFImageExtension",
    "Microsoft.NET.Native",
    "Microsoft.SecHealthUI",
    "Microsoft.Services.Store.Engagement",
    "Microsoft.StorePurchaseApp",
    "Microsoft.UI.Xaml",
    "Microsoft.VCLibs",
    "Microsoft.WindowsStore",
    "Microsoft.WindowsTerminal",
    "Microsoft.WindowsAppRuntime",
    // Named individually rather than as a "MicrosoftWindows.Client" prefix:
    // the shell components below are load-bearing, but the Widgets board ships
    // under the same prefix as Client.WebExperience and is safe to remove.
    "MicrosoftWindows.Client.CBS",
    "MicrosoftWindows.Client.Core",
    "MicrosoftWindows.Client.FileExp",
    "MicrosoftWindows.Client.OOBE",
    "MicrosoftWindows.Client.Photon",
    "Microsoft.AAD.BrokerPlugin",
    "Microsoft.AccountsControl",
    "Microsoft.Windows.ShellExperienceHost",
    "Microsoft.Windows.StartMenuExperienceHost",
    "Microsoft.Windows.CloudExperienceHost",
    "Microsoft.Windows.SecureAssessmentBrowser",
    "Windows.immersivecontrolpanel",
    "Microsoft.XboxGameCallableUI",
];

pub fn is_protected_service(name: &str) -> bool {
    SERVICES
        .iter()
        .any(|entry| entry.eq_ignore_ascii_case(name))
}

pub fn is_protected_package(package: &str) -> bool {
    let lowered = package.to_ascii_lowercase();
    PACKAGES
        .iter()
        .any(|entry| lowered.starts_with(&entry.to_ascii_lowercase()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn service_matching_ignores_case() {
        assert!(is_protected_service("windefend"));
        assert!(is_protected_service("WinDefend"));
        assert!(!is_protected_service("DiagTrack"));
    }

    #[test]
    fn package_matching_covers_versioned_names() {
        assert!(is_protected_package(
            "Microsoft.VCLibs.140.00_14.0.30704.0_x64__8wekyb3d8bbwe"
        ));
        assert!(is_protected_package("Microsoft.WindowsStore"));
        assert!(!is_protected_package("Microsoft.BingNews"));
    }
}
