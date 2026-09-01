//! Store app (Appx/MSIX) inspection and removal.
//!
//! Windows exposes package management through WinRT and PowerShell but not
//! through a stable C API worth binding, so this module shells out to
//! PowerShell. That is the same thing every other debloat tool does; the
//! difference here is the protected list below.

use crate::error::{Error, Result};
use crate::process;

pub fn is_protected(package: &str) -> bool {
    crate::protected::is_protected_package(package)
}

/// Rejects anything that could break out of the single-quoted PowerShell
/// string the package name is interpolated into.
///
/// Package names are ASCII identifiers with dots; nothing legitimate contains
/// a quote, a newline or a semicolon.
fn validate(package: &str) -> Result<()> {
    let acceptable = |c: char| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_' | '*');
    if package.is_empty() || !package.chars().all(acceptable) {
        return Err(Error::new(format!(
            "'{package}' is not a valid package name"
        )));
    }
    Ok(())
}

/// Whether the package is installed for this user or still provisioned for new
/// ones. A package can be either, both or neither.
pub fn state(package: &str) -> Result<(bool, bool)> {
    validate(package)?;

    let script = format!(
        "$ErrorActionPreference='SilentlyContinue';\
         $installed = @(Get-AppxPackage -Name '{package}').Count;\
         $provisioned = @(Get-AppxProvisionedPackage -Online | Where-Object {{ $_.DisplayName -like '{package}' }}).Count;\
         Write-Output \"$installed $provisioned\""
    );

    let result = process::powershell(&script)?;
    let text = result.stdout.trim().to_string();
    let mut parts = text.split_whitespace();
    let installed = parts
        .next()
        .and_then(|n| n.parse::<u32>().ok())
        .unwrap_or(0);
    let provisioned = parts
        .next()
        .and_then(|n| n.parse::<u32>().ok())
        .unwrap_or(0);

    Ok((installed > 0, provisioned > 0))
}

/// Removes a package for the current user and de-provisions it so it does not
/// come back for newly created accounts.
///
/// A package that is not installed is already in the state the caller wants,
/// so that is success rather than a failure to report.
pub fn remove(package: &str) -> Result<()> {
    validate(package)?;

    if is_protected(package) {
        return Err(Error::new(format!(
            "'{package}' is a protected package and will not be removed"
        )));
    }

    let script = format!(
        "$ErrorActionPreference='Stop'; $failed=@();\
         foreach ($p in @(Get-AppxPackage -Name '{package}')) {{\
           try {{ Remove-AppxPackage -Package $p.PackageFullName }} catch {{ $failed += $_.Exception.Message }} }}\
         foreach ($p in @(Get-AppxProvisionedPackage -Online | Where-Object {{ $_.DisplayName -like '{package}' }})) {{\
           try {{ Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName | Out-Null }} catch {{ $failed += $_.Exception.Message }} }}\
         if ($failed.Count) {{ Write-Error ($failed -join '; ') }}"
    );

    let result = process::powershell(&script)?;
    if result.ok() {
        Ok(())
    } else {
        Err(Error::new(format!(
            "removing {package}: {}",
            result.combined().trim()
        )))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_package_names_that_could_escape_the_script() {
        assert!(validate("Microsoft.BingNews").is_ok());
        assert!(validate("Microsoft.Xbox*").is_ok());
        assert!(validate("Evil'; Remove-Item C:\\ -Recurse; '").is_err());
        assert!(validate("with space").is_err());
        assert!(validate("").is_err());
    }
}
