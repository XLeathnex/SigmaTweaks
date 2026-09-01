//! Elevation checks and re-launching the app as administrator.

use crate::error::{Error, Result};

/// True when this process holds an elevated token.
pub fn is_elevated() -> bool {
    use windows::Win32::Foundation::CloseHandle;
    use windows::Win32::Security::{
        GetTokenInformation, TokenElevation, TOKEN_ELEVATION, TOKEN_QUERY,
    };
    use windows::Win32::System::Threading::{GetCurrentProcess, OpenProcessToken};

    // SAFETY: the token handle is closed on every path out, and the output
    // buffer is a correctly sized local of the type TokenElevation returns.
    unsafe {
        let mut token = Default::default();
        if OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token).is_err() {
            return false;
        }

        let mut elevation = TOKEN_ELEVATION::default();
        let mut returned = 0u32;
        let queried = GetTokenInformation(
            token,
            TokenElevation,
            Some(&mut elevation as *mut _ as *mut _),
            std::mem::size_of::<TOKEN_ELEVATION>() as u32,
            &mut returned,
        );

        let _ = CloseHandle(token);
        queried.is_ok() && elevation.TokenIsElevated != 0
    }
}

/// Relaunches this executable through the UAC prompt.
///
/// Returns once the new process has been started; the caller is expected to
/// exit so that two copies do not fight over the same registry keys.
pub fn relaunch_as_admin() -> Result<()> {
    use windows::core::{HSTRING, PCWSTR};
    use windows::Win32::UI::Shell::ShellExecuteW;
    use windows::Win32::UI::WindowsAndMessaging::SW_SHOWNORMAL;

    if is_elevated() {
        return Ok(());
    }

    let exe = std::env::current_exe()
        .map_err(|err| Error::new(format!("cannot locate the running executable: {err}")))?;
    let path = HSTRING::from(exe.as_os_str());
    let verb = HSTRING::from("runas");

    // SAFETY: both strings outlive the call. ShellExecuteW returns a value
    // above 32 on success; anything at or below is an error code, and the
    // common one here is the user declining the UAC prompt.
    let result = unsafe {
        ShellExecuteW(
            None,
            PCWSTR(verb.as_ptr()),
            PCWSTR(path.as_ptr()),
            PCWSTR::null(),
            PCWSTR::null(),
            SW_SHOWNORMAL,
        )
    };

    if result.0 as usize > 32 {
        Ok(())
    } else {
        Err(Error::new(
            "elevation was declined, so system-wide tweaks stay unavailable",
        ))
    }
}
