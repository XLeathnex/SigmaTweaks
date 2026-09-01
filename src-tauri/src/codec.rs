//! Registry value encoding, decoding and comparison.
//!
//! Kept free of any Windows binding so the fiddly parts - the DWORD sign
//! boundary, UTF-16 round-trips, comparing a number against its decimal
//! spelling - are testable on any machine.

use crate::error::{Error, Result};
use crate::model::{RegValue, ValueType};

/// The `REG_*` constants, which are stable numbers in the Windows ABI.
pub mod reg_type {
    pub const SZ: u32 = 1;
    pub const EXPAND_SZ: u32 = 2;
    pub const BINARY: u32 = 3;
    pub const DWORD: u32 = 4;
    pub const MULTI_SZ: u32 = 7;
    pub const QWORD: u32 = 11;
}

/// Which hive a registry path starts in.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Hive {
    LocalMachine,
    CurrentUser,
    ClassesRoot,
    Users,
    CurrentConfig,
}

/// Splits `HKLM:\SOFTWARE\Foo` into its hive and the rest of the path.
///
/// Accepts the `HKLM:\`, `HKLM\` and `HKEY_LOCAL_MACHINE\` spellings, because
/// all three turn up in the documentation people copy tweaks from.
pub fn split_path(path: &str) -> Result<(Hive, String)> {
    let normalised = path.trim().replace('/', "\\");
    let (hive, rest) = normalised
        .split_once('\\')
        .ok_or_else(|| Error::new(format!("registry path has no subkey: {path}")))?;

    let hive = match hive.trim_end_matches(':').to_ascii_uppercase().as_str() {
        "HKLM" | "HKEY_LOCAL_MACHINE" => Hive::LocalMachine,
        "HKCU" | "HKEY_CURRENT_USER" => Hive::CurrentUser,
        "HKCR" | "HKEY_CLASSES_ROOT" => Hive::ClassesRoot,
        "HKU" | "HKEY_USERS" => Hive::Users,
        "HKCC" | "HKEY_CURRENT_CONFIG" => Hive::CurrentConfig,
        other => return Err(Error::new(format!("unknown registry hive '{other}'"))),
    };

    Ok((hive, rest.to_string()))
}

pub fn reg_type_of(value_type: ValueType) -> u32 {
    match value_type {
        ValueType::Dword => reg_type::DWORD,
        ValueType::Qword => reg_type::QWORD,
        ValueType::String => reg_type::SZ,
        ValueType::ExpandString => reg_type::EXPAND_SZ,
        ValueType::MultiString => reg_type::MULTI_SZ,
        ValueType::Binary => reg_type::BINARY,
    }
}

pub fn value_type_of(raw: u32) -> ValueType {
    match raw {
        reg_type::DWORD => ValueType::Dword,
        reg_type::QWORD => ValueType::Qword,
        reg_type::EXPAND_SZ => ValueType::ExpandString,
        reg_type::MULTI_SZ => ValueType::MultiString,
        reg_type::SZ => ValueType::String,
        _ => ValueType::Binary,
    }
}

fn encode_utf16(text: &str) -> Vec<u8> {
    text.encode_utf16()
        .chain(std::iter::once(0))
        .flat_map(u16::to_le_bytes)
        .collect()
}

fn decode_utf16(bytes: &[u8]) -> String {
    let units: Vec<u16> = bytes
        .chunks_exact(2)
        .map(|pair| u16::from_le_bytes([pair[0], pair[1]]))
        .take_while(|unit| *unit != 0)
        .collect();
    String::from_utf16_lossy(&units)
}

fn hex_to_bytes(text: &str) -> Result<Vec<u8>> {
    let cleaned: String = text
        .chars()
        .filter(|c| !c.is_whitespace() && *c != ',')
        .collect();
    if cleaned.len() % 2 != 0 {
        return Err(Error::new("binary value has an odd number of hex digits"));
    }
    (0..cleaned.len())
        .step_by(2)
        .map(|i| {
            u8::from_str_radix(&cleaned[i..i + 2], 16)
                .map_err(|_| Error::new("binary value is not valid hex"))
        })
        .collect()
}

/// Encodes a catalog value into the bytes the registry stores.
///
/// A DWORD takes the low 32 bits of the `i64`, so a catalog value of `-1`
/// produces `0xFFFFFFFF` - which is how Windows spells "no limit" in values
/// like `NetworkThrottlingIndex`.
pub fn encode(value: &RegValue, value_type: ValueType) -> Result<Vec<u8>> {
    Ok(match (value, value_type) {
        (RegValue::Int(n), ValueType::Dword) => (*n as u32).to_le_bytes().to_vec(),
        (RegValue::Int(n), ValueType::Qword) => (*n as u64).to_le_bytes().to_vec(),
        (RegValue::Int(n), ValueType::String | ValueType::ExpandString) => {
            encode_utf16(&n.to_string())
        }
        (RegValue::Text(s), ValueType::String | ValueType::ExpandString) => encode_utf16(s),
        (RegValue::Text(s), ValueType::MultiString) => {
            let mut bytes: Vec<u8> = s.split('\0').flat_map(encode_utf16).collect();
            bytes.extend_from_slice(&[0, 0]);
            bytes
        }
        (RegValue::Text(s), ValueType::Binary) => hex_to_bytes(s)?,
        (RegValue::Int(n), ValueType::Binary) => vec![*n as u8],
        (value, kind) => return Err(Error::new(format!("cannot store {value:?} as {kind:?}"))),
    })
}

/// Turns raw registry bytes back into a catalog value for comparison.
pub fn decode(bytes: &[u8], raw_type: u32) -> RegValue {
    match raw_type {
        reg_type::DWORD => {
            let mut buffer = [0u8; 4];
            let len = bytes.len().min(4);
            buffer[..len].copy_from_slice(&bytes[..len]);
            // Round-trip through i32 so 0xFFFFFFFF compares equal to -1.
            RegValue::Int(i32::from_le_bytes(buffer) as i64)
        }
        reg_type::QWORD => {
            let mut buffer = [0u8; 8];
            let len = bytes.len().min(8);
            buffer[..len].copy_from_slice(&bytes[..len]);
            RegValue::Int(i64::from_le_bytes(buffer))
        }
        reg_type::SZ | reg_type::EXPAND_SZ | reg_type::MULTI_SZ => {
            RegValue::Text(decode_utf16(bytes))
        }
        _ => RegValue::Text(bytes.iter().map(|byte| format!("{byte:02x}")).collect()),
    }
}

/// Compares two values, treating a number and its decimal spelling as equal.
///
/// The catalog stores `MenuShowDelay` as the string "0" because that is how
/// Windows stores it, but a hand-edited profile may carry it as a number.
pub fn equivalent(a: &RegValue, b: &RegValue) -> bool {
    match (a, b) {
        (RegValue::Int(x), RegValue::Int(y)) => x == y,
        (RegValue::Text(x), RegValue::Text(y)) => x.eq_ignore_ascii_case(y),
        (RegValue::Int(x), RegValue::Text(y)) | (RegValue::Text(y), RegValue::Int(x)) => y
            .trim()
            .parse::<i64>()
            .map(|parsed| parsed == *x)
            .unwrap_or(false),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_every_hive_spelling() {
        for path in [
            "HKLM:\\SOFTWARE\\A",
            "HKLM\\SOFTWARE\\A",
            "HKEY_LOCAL_MACHINE\\SOFTWARE\\A",
            "hklm:\\SOFTWARE\\A",
        ] {
            let (hive, sub) = split_path(path).expect("should parse");
            assert_eq!(hive, Hive::LocalMachine);
            assert_eq!(sub, "SOFTWARE\\A");
        }
    }

    #[test]
    fn rejects_unknown_or_incomplete_paths() {
        assert!(split_path("HKXX\\Foo").is_err());
        assert!(split_path("HKLM").is_err());
    }

    #[test]
    fn dword_round_trips_across_the_sign_boundary() {
        // 0xFFFFFFFF is how Windows spells "no limit"; the catalog writes -1.
        let bytes = encode(&RegValue::Int(-1), ValueType::Dword).expect("encodes");
        assert_eq!(bytes, vec![0xFF, 0xFF, 0xFF, 0xFF]);
        assert_eq!(decode(&bytes, reg_type::DWORD), RegValue::Int(-1));
    }

    #[test]
    fn ordinary_dwords_round_trip() {
        for value in [0i64, 1, 2, 38, 4294967295u32 as i64 - 1] {
            let bytes = encode(&RegValue::Int(value), ValueType::Dword).expect("encodes");
            let decoded = decode(&bytes, reg_type::DWORD);
            let expected = RegValue::Int(value as u32 as i32 as i64);
            assert_eq!(decoded, expected, "value {value} did not survive the trip");
        }
    }

    #[test]
    fn strings_round_trip_as_nul_terminated_utf16() {
        let bytes = encode(&RegValue::Text("3000".into()), ValueType::String).expect("encodes");
        assert_eq!(bytes.last(), Some(&0));
        assert_eq!(decode(&bytes, reg_type::SZ), RegValue::Text("3000".into()));
    }

    #[test]
    fn a_string_value_survives_quotes() {
        // ShortcutNameTemplate really is stored with its quotes included.
        let template = "\"%s.lnk\"";
        let bytes = encode(&RegValue::Text(template.into()), ValueType::String).expect("encodes");
        assert_eq!(
            decode(&bytes, reg_type::SZ),
            RegValue::Text(template.into())
        );
    }

    #[test]
    fn qwords_round_trip() {
        let bytes = encode(&RegValue::Int(1 << 40), ValueType::Qword).expect("encodes");
        assert_eq!(decode(&bytes, reg_type::QWORD), RegValue::Int(1 << 40));
    }

    #[test]
    fn a_number_equals_its_decimal_spelling() {
        assert!(equivalent(&RegValue::Int(0), &RegValue::Text("0".into())));
        assert!(equivalent(&RegValue::Text("2".into()), &RegValue::Int(2)));
        assert!(!equivalent(&RegValue::Int(1), &RegValue::Text("0".into())));
        assert!(!equivalent(
            &RegValue::Int(1),
            &RegValue::Text("high".into())
        ));
    }

    #[test]
    fn string_comparison_ignores_case() {
        assert!(equivalent(
            &RegValue::Text("High".into()),
            &RegValue::Text("high".into())
        ));
    }

    #[test]
    fn binary_values_parse_from_hex() {
        let bytes =
            encode(&RegValue::Text("de ad be ef".into()), ValueType::Binary).expect("encodes");
        assert_eq!(bytes, vec![0xDE, 0xAD, 0xBE, 0xEF]);
        assert!(encode(&RegValue::Text("abc".into()), ValueType::Binary).is_err());
    }

    #[test]
    fn value_types_map_both_ways() {
        for kind in [
            ValueType::Dword,
            ValueType::Qword,
            ValueType::String,
            ValueType::ExpandString,
            ValueType::MultiString,
            ValueType::Binary,
        ] {
            assert_eq!(value_type_of(reg_type_of(kind)), kind);
        }
    }
}
