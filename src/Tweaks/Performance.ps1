<#
.SYNOPSIS
    Responsiveness and resource-usage tweaks.
.NOTES
    Every entry states the stock Windows 11 value in Default so that Revert
    restores the machine rather than guessing.
#>

@(
    @{
        Id              = 'perf.visualfx'
        Name            = 'Adjust visual effects for performance'
        Category        = 'Performance'
        Description     = 'Switches the Performance Options dialog to "Adjust for best performance", turning off window animations, shadows and fades. The single biggest perceived-latency win on low-end hardware.'
        Risk            = 'Low'
        Recommended     = $true
        RequiresAdmin   = $false
        RestartExplorer = $true
        Registry        = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Name = 'VisualFXSetting'; Type = 'DWord'; Value = 2; Default = 0 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarAnimations'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ListviewAlphaSelect'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\DWM'; Name = 'EnableAeroPeek'; Type = 'DWord'; Value = 0; Default = 1 }
        )
    }

    @{
        Id            = 'perf.transparency'
        Name          = 'Disable transparency effects'
        Category      = 'Performance'
        Description   = 'Turns off the acrylic/mica blur behind the Start menu, taskbar and settings surfaces. Saves a small but constant amount of GPU work.'
        Risk          = 'Low'
        Recommended   = $true
        RequiresAdmin = $false
        Registry      = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'EnableTransparency'; Type = 'DWord'; Value = 0; Default = 1 }
        )
    }

    @{
        Id            = 'perf.menudelay'
        Name          = 'Remove menu show delay'
        Category      = 'Performance'
        Description   = 'Drops the 400 ms delay before submenus open. Menus feel instant; nothing else changes.'
        Risk          = 'Low'
        Recommended   = $true
        RequiresAdmin = $false
        RequiresRestart = $true
        Registry      = @(
            @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'MenuShowDelay'; Type = 'String'; Value = '0'; Default = '400' }
        )
    }

    @{
        Id            = 'perf.startupdelay'
        Name          = 'Remove startup program delay'
        Category      = 'Performance'
        Description   = 'Windows holds startup apps back for about ten seconds after logon to let the desktop settle. This removes that wait.'
        Risk          = 'Low'
        Recommended   = $true
        RequiresAdmin = $false
        Registry      = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize'; Name = 'StartupDelayInMSec'; Type = 'DWord'; Value = 0; Default = $null }
        )
    }

    @{
        Id              = 'perf.priorityseparation'
        Name            = 'Favour foreground applications'
        Category        = 'Performance'
        Description     = 'Sets Win32PrioritySeparation to short, variable quanta with a 3:1 foreground boost. Helps the window you are using stay responsive while something heavy runs behind it.'
        Risk            = 'Low'
        Recommended     = $true
        RequiresRestart = $true
        Registry        = @(
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'; Name = 'Win32PrioritySeparation'; Type = 'DWord'; Value = 38; Default = 2 }
        )
    }

    @{
        Id              = 'perf.prefetch'
        Name            = 'Disable Prefetch (SSD only)'
        Category        = 'Performance'
        Description     = 'Prefetch pre-loads boot and application data to hide seek latency. On an SSD there is no seek latency to hide, so it is pure write amplification.'
        Risk            = 'Medium'
        RequiresRestart = $true
        Requires        = @{ Ssd = $true }
        Registry        = @(
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'; Name = 'EnablePrefetcher'; Type = 'DWord'; Value = 0; Default = 3 }
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'; Name = 'EnableSuperfetch'; Type = 'DWord'; Value = 0; Default = 3 }
        )
    }

    @{
        Id          = 'perf.sysmain'
        Name        = 'Disable SysMain / Superfetch (SSD only)'
        Category    = 'Performance'
        Description = 'SysMain caches frequently used apps into RAM ahead of time. On an SSD with 16 GB or more this mostly costs background disk I/O. Leave it on if you are on a hard disk.'
        Risk        = 'Medium'
        Requires    = @{ Ssd = $true }
        Services    = @(
            @{ Name = 'SysMain'; StartupType = 'Disabled'; Default = 'Automatic'; Stop = $true }
        )
    }

    @{
        Id              = 'perf.faststartup'
        Name            = 'Disable Fast Startup'
        Category        = 'Performance'
        Description     = 'Fast Startup hibernates the kernel on shutdown. It shortens boot but leaves drivers in a stale state, breaks dual-boot filesystem access and makes "shut down" not really shut down.'
        Risk            = 'Low'
        Recommended     = $true
        RequiresRestart = $true
        Registry        = @(
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name = 'HiberbootEnabled'; Type = 'DWord'; Value = 0; Default = 1 }
        )
    }

    @{
        Id              = 'perf.waittokill'
        Name            = 'Shorten service shutdown timeout'
        Category        = 'Performance'
        Description     = 'Cuts the grace period Windows gives services during shutdown from 5 s to 3 s. Shortens shutdown; anything slower than 3 s is killed rather than asked twice.'
        Risk            = 'Low'
        RequiresRestart = $true
        Registry        = @(
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control'; Name = 'WaitToKillServiceTimeout'; Type = 'String'; Value = '3000'; Default = '5000' }
        )
    }

    @{
        Id              = 'perf.powerthrottling'
        Name            = 'Disable power throttling'
        Category        = 'Performance'
        Description     = 'Stops Windows from parking background processes onto efficiency cores and lower clocks. Helps sustained background work; costs battery life on a laptop.'
        Risk            = 'Medium'
        RequiresRestart = $true
        Registry        = @(
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling'; Name = 'PowerThrottlingOff'; Type = 'DWord'; Value = 1; Default = $null }
        )
    }

    @{
        Id            = 'perf.backgroundapps'
        Name          = 'Disable background apps'
        Category      = 'Performance'
        Description   = 'Prevents Store apps from running and refreshing while you are not using them. Live tiles and app notifications stop updating in the background.'
        Risk          = 'Low'
        Recommended   = $true
        RequiresAdmin = $false
        Registry      = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; Name = 'GlobalUserDisabled'; Type = 'DWord'; Value = 1; Default = 0 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'BackgroundAppGlobalToggle'; Type = 'DWord'; Value = 0; Default = 1 }
        )
    }

    @{
        Id          = 'perf.lastaccess'
        Name        = 'Disable NTFS last-access timestamps'
        Category    = 'Performance'
        Description = 'NTFS writes a timestamp every time a file is read. Turning that off removes a metadata write from every read. Backup tools that key on last-access time are rare, but check yours.'
        Risk        = 'Low'
        Apply       = {
            $proc = Start-Process -FilePath 'fsutil.exe' -ArgumentList @('behavior', 'set', 'disablelastaccess', '1') -Wait -PassThru -NoNewWindow
            if ($proc.ExitCode -ne 0) {
                Write-SigmaLog "fsutil returned $($proc.ExitCode) while disabling last-access updates." -Level Warn
                return $false
            }
            return $true
        }
        Revert      = {
            $proc = Start-Process -FilePath 'fsutil.exe' -ArgumentList @('behavior', 'set', 'disablelastaccess', '2') -Wait -PassThru -NoNewWindow
            return ($proc.ExitCode -eq 0)
        }
        Test        = {
            $value = Get-SigmaRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'NtfsDisableLastAccessUpdate'
            if (-not $value.Exists) { return 'NotApplied' }
            # Bit 0 carries the setting; bit 31 only records "system managed".
            if (([int]$value.Value -band 1) -eq 1) { return 'Applied' }
            return 'NotApplied'
        }
    }

    @{
        Id              = 'perf.hibernation'
        Name            = 'Disable hibernation'
        Category        = 'Performance'
        Description     = 'Deletes hiberfil.sys, reclaiming roughly 40% of your RAM size in disk space. Also disables Fast Startup, which depends on it. Do not use this on a laptop you suspend to disk.'
        Risk            = 'Medium'
        RequiresRestart = $true
        Apply           = {
            $proc = Start-Process -FilePath 'powercfg.exe' -ArgumentList @('/hibernate', 'off') -Wait -PassThru -NoNewWindow
            return ($proc.ExitCode -eq 0)
        }
        Revert          = {
            $proc = Start-Process -FilePath 'powercfg.exe' -ArgumentList @('/hibernate', 'on') -Wait -PassThru -NoNewWindow
            return ($proc.ExitCode -eq 0)
        }
        Test            = {
            $value = Get-SigmaRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'HibernateEnabled'
            if (-not $value.Exists) { return 'Unknown' }
            return $(if ([int]$value.Value -eq 0) { 'Applied' } else { 'NotApplied' })
        }
    }

    @{
        Id          = 'perf.reservedstorage'
        Name        = 'Disable reserved storage'
        Category    = 'Performance'
        Description = 'Windows reserves about 7 GB for update staging. Disabling it returns that space now; feature updates will instead need free space at install time.'
        Risk        = 'Low'
        Requires    = @{ MinBuild = 19041 }
        Apply       = {
            if (-not (Get-Command -Name 'Set-WindowsReservedStorageState' -ErrorAction SilentlyContinue)) {
                Write-SigmaLog 'Set-WindowsReservedStorageState is unavailable on this build.' -Level Warn
                return $false
            }
            try {
                Set-WindowsReservedStorageState -State Disabled -ErrorAction Stop | Out-Null
                return $true
            } catch {
                Write-SigmaLog "Reserved storage could not be disabled: $($_.Exception.Message)" -Level Warn
                return $false
            }
        }
        Revert      = {
            try {
                Set-WindowsReservedStorageState -State Enabled -ErrorAction Stop | Out-Null
                return $true
            } catch {
                Write-SigmaLog "Reserved storage could not be re-enabled: $($_.Exception.Message)" -Level Warn
                return $false
            }
        }
        Test        = {
            try {
                $state = Get-WindowsReservedStorageState -ErrorAction Stop
                return $(if ($state.ReservedStorageState -eq 'Disabled') { 'Applied' } else { 'NotApplied' })
            } catch {
                return 'Unknown'
            }
        }
    }
)
