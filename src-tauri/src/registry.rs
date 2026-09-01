//! Registry reads and writes.
//!
//! Everything that touches the registry goes through here, so key creation and
//! missing-key handling behave identically for the engine, the backup writer
//! and the state detector. The encoding and comparison rules live in
//! [`crate::codec`], which has no Windows dependency and carries the tests.

use crate::codec::{self, Hive};
use crate::error::{Context, Error, Result};
use crate::model::{RegValue, ValueType};
use winreg::enums::*;
use winreg::{RegKey, RegValue as RawValue};

fn open_hive(hive: Hive) -> RegKey {
    RegKey::predef(match hive {
        Hive::LocalMachine => HKEY_LOCAL_MACHINE,
        Hive::CurrentUser => HKEY_CURRENT_USER,
        Hive::ClassesRoot => HKEY_CLASSES_ROOT,
        Hive::Users => HKEY_USERS,
        Hive::CurrentConfig => HKEY_CURRENT_CONFIG,
    })
}

fn split(path: &str) -> Result<(RegKey, String)> {
    let (hive, subkey) = codec::split_path(path)?;
    Ok((open_hive(hive), subkey))
}

/// winreg models value types as a fieldless enum rather than the raw REG_*
/// numbers the codec works in, so the two are mapped explicitly here instead
/// of relying on the enum's discriminant layout.
fn to_winreg_type(value_type: ValueType) -> RegType {
    match value_type {
        ValueType::Dword => RegType::REG_DWORD,
        ValueType::Qword => RegType::REG_QWORD,
        ValueType::String => RegType::REG_SZ,
        ValueType::ExpandString => RegType::REG_EXPAND_SZ,
        ValueType::MultiString => RegType::REG_MULTI_SZ,
        ValueType::Binary => RegType::REG_BINARY,
    }
}

fn from_winreg_type(raw: &RegType) -> u32 {
    match raw {
        RegType::REG_SZ => codec::reg_type::SZ,
        RegType::REG_EXPAND_SZ => codec::reg_type::EXPAND_SZ,
        RegType::REG_DWORD => codec::reg_type::DWORD,
        RegType::REG_QWORD => codec::reg_type::QWORD,
        RegType::REG_MULTI_SZ => codec::reg_type::MULTI_SZ,
        // Everything else is handled as opaque bytes.
        _ => codec::reg_type::BINARY,
    }
}

/// The current value at `path\name`, or `None` when the key or value is absent.
pub fn read(path: &str, name: &str) -> Result<Option<RegValue>> {
    Ok(read_typed(path, name)?.map(|(value, _)| value))
}

/// Reads a value along with the type Windows actually stored it as, which the
/// backup writer needs in order to restore it faithfully.
pub fn read_typed(path: &str, name: &str) -> Result<Option<(RegValue, ValueType)>> {
    let (hive, subkey) = split(path)?;
    let Ok(key) = hive.open_subkey_with_flags(&subkey, KEY_READ) else {
        return Ok(None);
    };
    let Ok(raw) = key.get_raw_value(name) else {
        return Ok(None);
    };

    let raw_type = from_winreg_type(&raw.vtype);
    Ok(Some((
        codec::decode(&raw.bytes, raw_type),
        codec::value_type_of(raw_type),
    )))
}

/// Writes a value, creating the key path when it does not exist yet.
pub fn write(path: &str, name: &str, value: &RegValue, value_type: ValueType) -> Result<()> {
    let (hive, subkey) = split(path)?;
    let (key, _) = hive
        .create_subkey_with_flags(&subkey, KEY_SET_VALUE | KEY_CREATE_SUB_KEY)
        .context(&format!("opening {path} for writing"))?;

    let raw = RawValue {
        bytes: codec::encode(value, value_type)?.into(),
        vtype: to_winreg_type(value_type),
    };

    key.set_raw_value(name, &raw)
        .context(&format!("writing {path}\\{name}"))
}

/// Deletes a value. A value that is already gone counts as success.
pub fn delete_value(path: &str, name: &str) -> Result<()> {
    let (hive, subkey) = split(path)?;
    let Ok(key) = hive.open_subkey_with_flags(&subkey, KEY_SET_VALUE) else {
        return Ok(());
    };
    match key.delete_value(name) {
        Ok(()) => Ok(()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(err) => Err(Error::new(format!("removing {path}\\{name}: {err}"))),
    }
}

/// Deletes a key and everything beneath it. A missing key counts as success.
pub fn delete_key(path: &str) -> Result<()> {
    let (hive, subkey) = split(path)?;
    match hive.delete_subkey_all(&subkey) {
        Ok(()) => Ok(()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(err) => Err(Error::new(format!("removing key {path}: {err}"))),
    }
}

/// Names of the immediate subkeys of `path`, empty when the key is absent.
pub fn subkeys(path: &str) -> Result<Vec<String>> {
    let (hive, subkey) = split(path)?;
    let Ok(key) = hive.open_subkey_with_flags(&subkey, KEY_READ) else {
        return Ok(Vec::new());
    };
    Ok(key
        .enum_keys()
        .filter_map(std::result::Result::ok)
        .collect())
}

/// True when the live value equals `expected`. `None` means "should not exist".
pub fn matches(path: &str, name: &str, expected: Option<&RegValue>) -> bool {
    let current = read(path, name).unwrap_or(None);
    match (current, expected) {
        (None, None) => true,
        (None, Some(_)) | (Some(_), None) => false,
        (Some(actual), Some(wanted)) => codec::equivalent(&actual, wanted),
    }
}
