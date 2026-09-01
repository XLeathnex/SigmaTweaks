//! Parsing of the console output state detection reads.
//!
//! Kept free of Windows bindings so the fiddly parts - quoted commas inside a
//! scheduled task name, package wildcards - are testable on any machine.

/// Pulls the task path and enabled flag out of one schtasks CSV row.
pub fn parse_task_row(line: &str) -> Option<(String, bool)> {
    let fields = split_csv(line);
    let name = fields.first()?.trim();
    let status = fields.get(2)?.trim();

    if name.is_empty() || status.is_empty() || name.eq_ignore_ascii_case("TaskName") {
        return None;
    }

    Some((
        name.to_ascii_lowercase(),
        !status.eq_ignore_ascii_case("Disabled"),
    ))
}

/// Splits a schtasks CSV row. Task names can contain commas, so quoted fields
/// have to be respected rather than splitting on the separator alone.
pub fn split_csv(line: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut current = String::new();
    let mut quoted = false;

    for c in line.chars() {
        match c {
            '"' => quoted = !quoted,
            ',' if !quoted => fields.push(std::mem::take(&mut current)),
            _ => current.push(c),
        }
    }
    fields.push(current);
    fields
}

/// Matches a catalog package pattern against a package name.
///
/// Patterns are exact names or a prefix followed by `*`, matched without
/// regard to case, which is how the catalog spells things like
/// `Microsoft.Xbox*`.
pub fn pattern_matches(pattern: &str, name: &str) -> bool {
    let pattern = pattern.to_ascii_lowercase();
    let name = name.to_ascii_lowercase();
    match pattern.strip_suffix('*') {
        Some(prefix) => name.starts_with(prefix),
        None => name == pattern,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_a_schtasks_row() {
        let row = "\"\\Microsoft\\Windows\\Autochk\\Proxy\",\"N/A\",\"Disabled\"";
        let (name, enabled) = parse_task_row(row).expect("row parses");
        assert_eq!(name, "\\microsoft\\windows\\autochk\\proxy");
        assert!(!enabled);
    }

    #[test]
    fn treats_ready_and_running_as_enabled() {
        for status in ["Ready", "Running"] {
            let row = format!("\"\\Task\",\"N/A\",\"{status}\"");
            assert_eq!(parse_task_row(&row), Some(("\\task".into(), true)));
        }
    }

    #[test]
    fn skips_the_header_and_blank_rows() {
        assert_eq!(
            parse_task_row("\"TaskName\",\"Next Run Time\",\"Status\""),
            None
        );
        assert_eq!(parse_task_row(""), None);
    }

    #[test]
    fn respects_quotes_around_a_comma_in_a_task_name() {
        let row = "\"\\Vendor\\Update, daily\",\"N/A\",\"Ready\"";
        let (name, enabled) = parse_task_row(row).expect("row parses");
        assert_eq!(name, "\\vendor\\update, daily");
        assert!(enabled);
    }

    #[test]
    fn package_patterns_match_prefixes_and_exact_names() {
        assert!(pattern_matches("Microsoft.BingNews", "microsoft.bingnews"));
        assert!(pattern_matches(
            "Microsoft.Xbox*",
            "Microsoft.XboxGamingOverlay"
        ));
        assert!(!pattern_matches(
            "Microsoft.Xbox",
            "Microsoft.XboxGamingOverlay"
        ));
        assert!(!pattern_matches(
            "Microsoft.BingNews",
            "Microsoft.BingWeather"
        ));
    }
}
