//! Data model for the tweak catalog.
//!
//! Tweaks are data, not code: `resources/catalog.json` is embedded at compile
//! time and deserialises straight into these types. A tweak lists the changes
//! it makes, and the engine derives apply, revert and state detection from
//! that list. The handful of changes that cannot be expressed as a list of
//! values use [`Action::Custom`], which names an operation implemented in
//! `custom.rs`.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Risk {
    /// Cosmetic or clearly beneficial.
    Low,
    /// A real trade-off; the description explains what it costs.
    Medium,
    /// Removes functionality the user may depend on.
    High,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ValueType {
    Dword,
    Qword,
    String,
    ExpandString,
    MultiString,
    Binary,
}

/// A registry value as it appears in the catalog. Numbers stay `i64` so that
/// `0xFFFFFFFF` can be written as `-1`, which is the same 32 bits.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum RegValue {
    Int(i64),
    Text(String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum StartupType {
    Automatic,
    Manual,
    Disabled,
}

impl StartupType {
    /// The `Start` value the service control manager stores in the registry.
    pub fn start_value(self) -> u32 {
        match self {
            StartupType::Automatic => 2,
            StartupType::Manual => 3,
            StartupType::Disabled => 4,
        }
    }

    pub fn from_start_value(value: u32) -> Option<Self> {
        match value {
            2 => Some(StartupType::Automatic),
            3 => Some(StartupType::Manual),
            4 => Some(StartupType::Disabled),
            _ => None,
        }
    }

    pub fn sc_argument(self) -> &'static str {
        match self {
            StartupType::Automatic => "auto",
            StartupType::Manual => "demand",
            StartupType::Disabled => "disabled",
        }
    }
}

/// Changes that cannot be described as "write this value here".
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CustomOp {
    /// NumLock on at sign-in, for both the current user and the logon screen.
    NumLock,
    /// The Windows 10 style right-click menu.
    ClassicContextMenu,
    /// Nagle's algorithm, per network interface.
    Nagle,
    /// NetBIOS over TCP/IP, per network interface.
    Netbios,
    /// Cloudflare resolvers on every connected adapter.
    CloudflareDns,
    /// NTFS last-access timestamps, via fsutil.
    NtfsLastAccess,
    /// Hibernation and hiberfil.sys, via powercfg.
    Hibernation,
    /// The ~7 GB update staging reservation.
    ReservedStorage,
    /// The hidden Ultimate Performance power scheme.
    UltimatePerformance,
    /// USB selective suspend on the active scheme.
    UsbSelectiveSuspend,
    /// Sleep and hibernate timers on AC power.
    NeverSleepAc,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Action {
    Registry {
        path: String,
        name: String,
        value_type: ValueType,
        /// The value to write when applying. `None` deletes it.
        value: Option<RegValue>,
        /// The stock Windows value, written when reverting. `None` deletes it.
        default: Option<RegValue>,
        /// Extra values that also count as "already applied".
        ///
        /// Detection has to recognise work someone else did. Other tools, and
        /// the Windows UI itself, often reach the same end state through a
        /// different number: `Win32PrioritySeparation` is 0x26 here but 0x28
        /// and 0x2A are equally short-quantum, and telemetry set to Basic
        /// through Settings lands on 1 where the policy writes 0. Anything
        /// listed here reads as applied but is never written.
        #[serde(default)]
        accepts: Vec<RegValue>,
    },
    Service {
        name: String,
        startup: StartupType,
        default: StartupType,
        #[serde(default)]
        stop: bool,
        /// Startup types that also count as "already applied", for the same
        /// reason as `accepts` above: a service someone already set to Manual
        /// when this tweak wants Disabled is most of the way there, and
        /// reporting it as untouched would be wrong.
        #[serde(default)]
        accepts: Vec<StartupType>,
    },
    ScheduledTask {
        path: String,
        name: String,
    },
    Appx {
        package: String,
    },
    Custom {
        op: CustomOp,
    },
}

/// Conditions under which a tweak is worth offering at all.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Requires {
    #[serde(default)]
    pub windows11: bool,
    #[serde(default)]
    pub min_build: Option<u32>,
    #[serde(default)]
    pub ssd: bool,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tweak {
    pub id: String,
    pub name: String,
    pub category: String,
    pub description: String,
    pub risk: Risk,
    #[serde(default)]
    pub recommended: bool,
    #[serde(default)]
    pub requires_restart: bool,
    #[serde(default)]
    pub restart_explorer: bool,
    /// Applying this cannot be undone by SigmaTweaks (Store app removal).
    #[serde(default)]
    pub irreversible: bool,
    #[serde(default = "default_true")]
    pub requires_admin: bool,
    #[serde(default)]
    pub requires: Option<Requires>,
    pub actions: Vec<Action>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum State {
    /// Every value this tweak sets is already in place.
    Applied,
    /// None of them are.
    NotApplied,
    /// Some are and some are not, usually after a Windows update reset one.
    Partial,
    /// The state cannot be read, so neither answer would be honest.
    Unknown,
    /// The tweak does not apply to this machine.
    NotApplicable,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Mode {
    Apply,
    Revert,
}

/// What the applicability rules need to know about this machine.
///
/// Passed in rather than read globally so that the rules are a pure function
/// of the host, and can be tested for a Windows 10 laptop with a spinning disk
/// on a machine that is neither.
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize)]
pub struct HostFacts {
    pub build: u32,
    pub is_windows11: bool,
    /// `None` when the media type could not be determined.
    pub is_ssd: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Preset {
    pub key: String,
    pub name: String,
    pub description: String,
    pub tweaks: Vec<String>,
}

/// A maintenance job: something you run, with no state and no revert.
#[derive(Debug, Clone, Serialize)]
pub struct MaintenanceAction {
    pub id: &'static str,
    pub name: &'static str,
    pub category: &'static str,
    pub description: &'static str,
    /// The UI asks before running these.
    pub confirm: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TweakResult {
    pub id: String,
    pub name: String,
    pub success: bool,
    pub message: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct TweakStatus {
    pub id: String,
    pub state: State,
    /// Why the tweak is `NotApplicable`, shown under its name.
    pub reason: Option<String>,
    /// How many of this tweak's checkable changes are already in place, and
    /// how many there are. The UI turns this into "3 of 4 already set", which
    /// is the difference between a useful Partial and a mystifying one.
    pub matched: u32,
    pub total: u32,
}
