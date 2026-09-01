//! The embedded tweak catalog and presets.
//!
//! `resources/catalog.json` is compiled into the binary, so there is no
//! runtime file to lose, tamper with or ship out of sync. Deserialisation is
//! the schema check: a registry action whose JSON omits `default` fails to
//! parse rather than becoming a tweak that cannot be reverted.

use crate::model::{HostFacts, Preset, Requires, Tweak};
use std::sync::OnceLock;

const CATALOG_JSON: &str = include_str!("../resources/catalog.json");
const PRESETS_JSON: &str = include_str!("../resources/presets.json");

/// The order categories appear in the sidebar.
const CATEGORY_ORDER: &[&str] = &[
    "Performance",
    "Gaming",
    "Privacy",
    "Network",
    "Explorer",
    "Services",
    "Updates",
    "Power",
    "Debloat",
];

pub fn tweaks() -> &'static [Tweak] {
    static CACHE: OnceLock<Vec<Tweak>> = OnceLock::new();
    CACHE.get_or_init(|| {
        serde_json::from_str(CATALOG_JSON).expect("the embedded catalog must be valid")
    })
}

pub fn presets() -> &'static [Preset] {
    static CACHE: OnceLock<Vec<Preset>> = OnceLock::new();
    CACHE.get_or_init(|| {
        serde_json::from_str(PRESETS_JSON).expect("the embedded presets must be valid")
    })
}

pub fn by_id(id: &str) -> Option<&'static Tweak> {
    tweaks().iter().find(|tweak| tweak.id == id)
}

/// Resolves ids to tweaks, accepting `privacy.*` style patterns and dropping
/// duplicates so `-Apply privacy.telemetry,privacy.*` runs each tweak once.
pub fn resolve(ids: &[String]) -> Vec<&'static Tweak> {
    let mut found: Vec<&'static Tweak> = Vec::new();

    for pattern in ids {
        let matched: Vec<&'static Tweak> = if let Some(prefix) = pattern.strip_suffix('*') {
            tweaks()
                .iter()
                .filter(|t| t.id.starts_with(prefix))
                .collect()
        } else {
            by_id(pattern).into_iter().collect()
        };

        for tweak in matched {
            if !found.iter().any(|existing| existing.id == tweak.id) {
                found.push(tweak);
            }
        }
    }

    found
}

/// Category names in display order, with any not in the preferred list last.
pub fn categories() -> Vec<&'static str> {
    let mut ordered: Vec<&'static str> = CATEGORY_ORDER
        .iter()
        .copied()
        .filter(|name| tweaks().iter().any(|tweak| tweak.category == *name))
        .collect();

    let mut extra: Vec<&'static str> = tweaks()
        .iter()
        .map(|tweak| tweak.category.as_str())
        .filter(|name| !ordered.contains(name))
        .collect();
    extra.sort_unstable();
    extra.dedup();
    ordered.extend(extra);

    ordered
}

/// Why this tweak does not apply to this machine, or `None` when it does.
pub fn not_applicable_reason(tweak: &Tweak, facts: &HostFacts) -> Option<String> {
    let Requires {
        windows11,
        min_build,
        ssd,
    } = tweak.requires.clone().unwrap_or_default();

    if windows11 && !facts.is_windows11 {
        return Some("Windows 11 only".into());
    }

    if let Some(minimum) = min_build {
        // A build of 0 means the version could not be read; do not block on it.
        if facts.build > 0 && facts.build < minimum {
            return Some(format!("needs build {minimum} or newer"));
        }
    }

    // Only block when the disk is known to be spinning rust. An unknown media
    // type leaves the choice to the user rather than hiding the tweak.
    if ssd && facts.is_ssd == Some(false) {
        return Some("only useful on an SSD".into());
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Action;
    use std::collections::HashSet;

    #[test]
    fn catalog_parses_and_is_not_empty() {
        assert!(tweaks().len() > 50, "catalog looks truncated");
    }

    #[test]
    fn every_id_is_unique() {
        let mut seen = HashSet::new();
        for tweak in tweaks() {
            assert!(seen.insert(&tweak.id), "duplicate tweak id: {}", tweak.id);
        }
    }

    #[test]
    fn every_tweak_does_something() {
        for tweak in tweaks() {
            assert!(!tweak.actions.is_empty(), "{} has no actions", tweak.id);
        }
    }

    #[test]
    fn every_tweak_is_explained() {
        for tweak in tweaks() {
            assert!(!tweak.name.is_empty(), "{} has no name", tweak.id);
            assert!(
                tweak.description.len() >= 20,
                "{} needs a real description",
                tweak.id
            );
            assert!(
                CATEGORY_ORDER.contains(&tweak.category.as_str()),
                "{} is in unknown category {}",
                tweak.id,
                tweak.category
            );
        }
    }

    #[test]
    fn appx_removal_is_declared_irreversible() {
        // Nothing can put an uninstalled Store app back, so a debloat tweak
        // that claims to be revertible would be lying to the user.
        for tweak in tweaks() {
            let removes_app = tweak
                .actions
                .iter()
                .any(|action| matches!(action, Action::Appx { .. }));
            if removes_app {
                assert!(
                    tweak.irreversible,
                    "{} removes an app but is not marked irreversible",
                    tweak.id
                );
            }
        }
    }

    #[test]
    fn no_tweak_touches_a_protected_service() {
        for tweak in tweaks() {
            for action in &tweak.actions {
                if let Action::Service { name, .. } = action {
                    assert!(
                        !crate::protected::is_protected_service(name),
                        "{} tries to reconfigure protected service {name}",
                        tweak.id
                    );
                }
            }
        }
    }

    #[test]
    fn no_tweak_removes_a_protected_package() {
        for tweak in tweaks() {
            for action in &tweak.actions {
                if let Action::Appx { package } = action {
                    assert!(
                        !crate::protected::is_protected_package(package),
                        "{} tries to remove protected package {package}",
                        tweak.id
                    );
                }
            }
        }
    }

    #[test]
    fn security_features_are_left_alone() {
        // SigmaTweaks does not trade the user's security for a placebo. If a
        // tweak ever starts writing to one of these, this test is the alarm.
        const FORBIDDEN: &[&str] = &[
            "policies\\microsoft\\windows defender",
            "windows defender\\real-time protection",
            "smartscreen",
            "\\system\\enablelua",
            "policies\\microsoft\\windowsfirewall",
        ];

        for tweak in tweaks() {
            for action in &tweak.actions {
                if let Action::Registry { path, name, .. } = action {
                    let target = format!("{path}\\{name}").to_ascii_lowercase();
                    for pattern in FORBIDDEN {
                        assert!(
                            !target.contains(pattern),
                            "{} writes to a security setting: {target}",
                            tweak.id
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn presets_only_reference_real_tweaks() {
        for preset in presets() {
            assert!(!preset.tweaks.is_empty(), "preset {} is empty", preset.key);
            for id in &preset.tweaks {
                assert!(
                    by_id(id).is_some(),
                    "preset {} references unknown id {id}",
                    preset.key
                );
            }
        }
    }

    #[test]
    fn the_recommended_preset_removes_no_apps() {
        // "Recommended" has to be safe to accept without reading it, which
        // means nothing in it can be one-way.
        let recommended = presets()
            .iter()
            .find(|preset| preset.key == "recommended")
            .expect("the recommended preset must exist");

        for id in &recommended.tweaks {
            let tweak = by_id(id).expect("preset ids are checked elsewhere");
            assert!(
                !tweak.irreversible,
                "{id} cannot be undone, so it does not belong in Recommended"
            );
        }
    }

    #[test]
    fn wildcards_resolve_and_deduplicate() {
        let all_privacy = resolve(&["privacy.*".to_string()]);
        assert!(all_privacy.len() > 5);

        let with_duplicate = resolve(&["privacy.telemetry".into(), "privacy.*".into()]);
        assert_eq!(with_duplicate.len(), all_privacy.len());
    }

    #[test]
    fn unknown_ids_resolve_to_nothing() {
        assert!(resolve(&["nope.nothing".to_string()]).is_empty());
    }

    #[test]
    fn windows_10_hides_the_windows_11_tweaks() {
        let win10 = HostFacts {
            build: 19045,
            is_windows11: false,
            is_ssd: None,
        };
        let blocked: Vec<&str> = tweaks()
            .iter()
            .filter(|tweak| not_applicable_reason(tweak, &win10).is_some())
            .map(|tweak| tweak.id.as_str())
            .collect();

        assert!(blocked.contains(&"explorer.taskbarleft"));
        assert!(!blocked.contains(&"privacy.telemetry"));
    }

    #[test]
    fn windows_11_allows_everything_a_modern_build_supports() {
        let win11 = HostFacts {
            build: 26100,
            is_windows11: true,
            is_ssd: Some(true),
        };
        for tweak in tweaks() {
            assert_eq!(
                not_applicable_reason(tweak, &win11),
                None,
                "{} was blocked on a current Windows 11 build",
                tweak.id
            );
        }
    }

    #[test]
    fn ssd_only_tweaks_are_hidden_on_a_hard_disk_but_not_on_an_unknown_one() {
        let hdd = HostFacts {
            build: 26100,
            is_windows11: true,
            is_ssd: Some(false),
        };
        let unknown = HostFacts {
            build: 26100,
            is_windows11: true,
            is_ssd: None,
        };
        let prefetch = by_id("perf.prefetch").expect("perf.prefetch exists");

        assert!(not_applicable_reason(prefetch, &hdd).is_some());
        assert_eq!(not_applicable_reason(prefetch, &unknown), None);
    }

    #[test]
    fn an_unreadable_build_number_blocks_nothing() {
        // build 0 means "could not read it", which must not hide tweaks.
        let unknown = HostFacts {
            build: 0,
            is_windows11: true,
            is_ssd: None,
        };
        let hags = by_id("gaming.hags").expect("gaming.hags exists");
        assert_eq!(not_applicable_reason(hags, &unknown), None);
    }

    #[test]
    fn categories_are_ordered_for_display() {
        let ordered = categories();
        assert_eq!(ordered.first(), Some(&"Performance"));
        assert!(ordered.contains(&"Debloat"));
    }
}
