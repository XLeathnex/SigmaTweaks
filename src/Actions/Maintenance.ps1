<#
.SYNOPSIS
    One-shot maintenance actions.
.DESCRIPTION
    Actions are things you run, not settings you toggle, so they have no state
    and no revert. Each entry supplies a Run scriptblock returning $true on
    success. Destructive ones set Confirm so the UI asks first.
#>

@(
    @{
        Id          = 'action.restorepoint'
        Name        = 'Create a restore point'
        Category    = 'Safety'
        Description = 'Takes a System Restore checkpoint you can roll back to from Windows Recovery.'
        Run         = { return (New-SigmaRestorePoint -Description 'SigmaTweaks manual checkpoint') }
    }

    @{
        Id          = 'action.systemprotection'
        Name        = 'Turn on System Protection'
        Category    = 'Safety'
        Description = 'Enables System Restore for the system drive. Restore points cannot be taken at all until this is on, and Windows ships with it off on many OEM installs. It reserves a few percent of the drive.'
        Confirm     = $true
        Run         = { return (Enable-SigmaSystemRestore) }
    }

    @{
        Id          = 'action.cleantemp'
        Name        = 'Clean temporary files'
        Category    = 'Cleanup'
        Description = 'Empties the user and system temp folders, the Windows prefetch cache and leftover Windows Update download files.'
        Confirm     = $true
        Run         = {
            $targets = @(
                $env:TEMP
                (Join-Path $env:SystemRoot 'Temp')
                (Join-Path $env:SystemRoot 'Prefetch')
            )

            $freed = 0
            foreach ($target in $targets) {
                if (-not $target -or -not (Test-Path -LiteralPath $target)) { continue }

                $items = Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue
                foreach ($item in $items) {
                    try {
                        $size = if ($item.PSIsContainer) {
                            (Get-ChildItem -LiteralPath $item.FullName -Recurse -Force -File -ErrorAction SilentlyContinue |
                                Measure-Object -Property Length -Sum).Sum
                        } else {
                            $item.Length
                        }

                        Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                        if ($size) { $freed += $size }
                    } catch {
                        # Files in use are expected here and are simply skipped.
                    }
                }
                Write-SigmaLog "Cleaned $target" -Level Debug
            }

            Write-SigmaLog ('Freed {0:N1} MB of temporary files.' -f ($freed / 1MB)) -Level Success
            return $true
        }
    }

    @{
        Id          = 'action.recyclebin'
        Name        = 'Empty the Recycle Bin'
        Category    = 'Cleanup'
        Description = 'Permanently deletes everything currently in the Recycle Bin on every drive.'
        Confirm     = $true
        Run         = {
            try {
                Clear-RecycleBin -Force -ErrorAction Stop
                Write-SigmaLog 'Recycle Bin emptied.' -Level Success
                return $true
            } catch {
                # Clear-RecycleBin throws when the bin is already empty.
                Write-SigmaLog "Recycle Bin: $($_.Exception.Message)" -Level Warn
                return $true
            }
        }
    }

    @{
        Id          = 'action.updatecache'
        Name        = 'Clear the Windows Update cache'
        Category    = 'Cleanup'
        Description = 'Stops Windows Update, deletes its downloaded package cache and starts it again. Fixes updates that fail repeatedly and reclaims several gigabytes.'
        Confirm     = $true
        Run         = {
            $services = @('wuauserv', 'bits')
            foreach ($name in $services) {
                Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
            }

            $cache = Join-Path $env:SystemRoot 'SoftwareDistribution\Download'
            if (Test-Path -LiteralPath $cache) {
                Get-ChildItem -LiteralPath $cache -Force -ErrorAction SilentlyContinue |
                    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }

            foreach ($name in $services) {
                Start-Service -Name $name -ErrorAction SilentlyContinue
            }

            Write-SigmaLog 'Windows Update cache cleared.' -Level Success
            return $true
        }
    }

    @{
        Id          = 'action.storecache'
        Name        = 'Reset the Microsoft Store cache'
        Category    = 'Cleanup'
        Description = 'Runs wsreset, which clears the Store cache without touching installed apps. Fixes downloads that hang at 0%.'
        Run         = {
            $proc = Start-Process -FilePath 'wsreset.exe' -ArgumentList '-i' -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
            if (-not $proc) {
                Write-SigmaLog 'wsreset.exe could not be started.' -Level Warn
                return $false
            }
            Write-SigmaLog 'Store cache reset started.' -Level Success
            return $true
        }
    }

    @{
        Id          = 'action.iconcache'
        Name        = 'Rebuild the icon cache'
        Category    = 'Cleanup'
        Description = 'Deletes the icon and thumbnail cache databases and restarts Explorer. Fixes blank or wrong icons on the desktop.'
        Confirm     = $true
        Run         = {
            $cacheDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
            Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500

            Get-ChildItem -LiteralPath $cacheDir -Filter 'iconcache*' -Force -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
            Get-ChildItem -LiteralPath $cacheDir -Filter 'thumbcache*' -Force -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue

            if (-not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) {
                Start-Process -FilePath 'explorer.exe'
            }
            Write-SigmaLog 'Icon cache rebuilt.' -Level Success
            return $true
        }
    }

    @{
        Id          = 'action.flushdns'
        Name        = 'Flush the DNS cache'
        Category    = 'Network'
        Description = 'Clears cached name lookups. Fixes a site that resolves to a stale address.'
        Run         = {
            $proc = Start-Process -FilePath 'ipconfig.exe' -ArgumentList '/flushdns' -Wait -PassThru -NoNewWindow
            Write-SigmaLog 'DNS resolver cache flushed.' -Level Success
            return ($proc.ExitCode -eq 0)
        }
    }

    @{
        Id          = 'action.resetnetwork'
        Name        = 'Reset the network stack'
        Category    = 'Network'
        Description = 'Resets Winsock and the TCP/IP stack to their defaults. A last resort for a machine that will not connect. Requires a restart, and clears any manual proxy or static IP configuration.'
        Confirm     = $true
        Run         = {
            $steps = @(
                @('winsock', 'reset')
                @('int', 'ip', 'reset')
                @('advfirewall', 'reset')
            )
            $ok = $true
            foreach ($step in $steps) {
                $proc = Start-Process -FilePath 'netsh.exe' -ArgumentList $step -Wait -PassThru -NoNewWindow
                if ($proc.ExitCode -ne 0) {
                    Write-SigmaLog "netsh $($step -join ' ') returned $($proc.ExitCode)." -Level Warn
                    $ok = $false
                }
            }
            Write-SigmaLog 'Network stack reset. Restart to finish.' -Level Warn
            return $ok
        }
    }

    @{
        Id          = 'action.sfc'
        Name        = 'Check system files (SFC)'
        Category    = 'Repair'
        Description = 'Runs sfc /scannow to verify and repair protected system files. Takes several minutes.'
        Run         = {
            Write-SigmaLog 'Running sfc /scannow - this takes a few minutes...' -Level Info
            $proc = Start-Process -FilePath 'sfc.exe' -ArgumentList '/scannow' -Wait -PassThru -NoNewWindow
            switch ($proc.ExitCode) {
                0 { Write-SigmaLog 'SFC finished; no integrity violations or all repaired.' -Level Success; return $true }
                default {
                    Write-SigmaLog "SFC exited with code $($proc.ExitCode). See CBS.log for detail." -Level Warn
                    return $false
                }
            }
        }
    }

    @{
        Id          = 'action.dism'
        Name        = 'Repair the component store (DISM)'
        Category    = 'Repair'
        Description = 'Runs DISM /RestoreHealth to repair the component store that SFC repairs from. Run this first if SFC cannot fix a file. Needs an internet connection and takes a while.'
        Run         = {
            Write-SigmaLog 'Running DISM /Online /Cleanup-Image /RestoreHealth...' -Level Info
            $proc = Start-Process -FilePath 'DISM.exe' `
                -ArgumentList @('/Online', '/Cleanup-Image', '/RestoreHealth') -Wait -PassThru -NoNewWindow
            if ($proc.ExitCode -eq 0) {
                Write-SigmaLog 'Component store repaired.' -Level Success
                return $true
            }
            Write-SigmaLog "DISM exited with code $($proc.ExitCode)." -Level Warn
            return $false
        }
    }

    @{
        Id          = 'action.optimizedrives'
        Name        = 'Optimize drives (TRIM / defrag)'
        Category    = 'Repair'
        Description = 'Sends TRIM to SSDs and defragments hard disks, choosing the right operation per drive.'
        Run         = {
            $volumes = @(Get-Volume -ErrorAction SilentlyContinue |
                Where-Object { $_.DriveLetter -and $_.FileSystemType -eq 'NTFS' -and $_.DriveType -eq 'Fixed' })

            if ($volumes.Count -eq 0) {
                Write-SigmaLog 'No fixed NTFS volumes found.' -Level Warn
                return $false
            }

            foreach ($volume in $volumes) {
                try {
                    Write-SigmaLog "Optimizing $($volume.DriveLetter): ..." -Level Info
                    Optimize-Volume -DriveLetter $volume.DriveLetter -ErrorAction Stop
                } catch {
                    Write-SigmaLog "Could not optimize $($volume.DriveLetter): $($_.Exception.Message)" -Level Warn
                }
            }
            Write-SigmaLog 'Drive optimization finished.' -Level Success
            return $true
        }
    }

    @{
        Id          = 'action.eventlogs'
        Name        = 'Clear all event logs'
        Category    = 'Cleanup'
        Description = 'Wipes every Windows event log. This destroys the crash and error history you would need to diagnose a problem later, so only do it when you are deliberately clearing traces of a fixed issue.'
        Confirm     = $true
        Run         = {
            $cleared = 0
            foreach ($log in (wevtutil.exe el)) {
                try {
                    wevtutil.exe cl "$log" 2>$null
                    $cleared++
                } catch {
                    # Some logs are locked or read-only by design.
                }
            }
            Write-SigmaLog "Cleared $cleared event logs." -Level Success
            return $true
        }
    }
)
