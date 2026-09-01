<#
.SYNOPSIS
    System restore points and per-run configuration snapshots.
.DESCRIPTION
    Before any tweak is applied, SigmaTweaks records the exact prior state of
    every registry value, service and scheduled task that tweak touches. That
    snapshot is what "Restore from backup" replays, and it is more accurate
    than a tweak's declared default because it reflects what was really there.
#>

function Enable-SigmaSystemRestore {
    <#
    .SYNOPSIS
        Turns System Protection on for the system drive.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if (-not $PSCmdlet.ShouldProcess($env:SystemDrive, 'Enable System Restore')) { return $true }

    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        Write-SigmaLog "System Restore enabled for $env:SystemDrive." -Level Success
        return $true
    } catch {
        Write-SigmaLog "Could not enable System Restore: $($_.Exception.Message)" -Level Warn
        return $false
    }
}

function New-SigmaRestorePoint {
    <#
    .SYNOPSIS
        Creates a system restore point.
    .DESCRIPTION
        Windows silently refuses more than one restore point per 24 hours. The
        frequency gate is temporarily set to 0 so that a point is actually
        created, then restored to whatever it was before.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string] $Description = 'SigmaTweaks'
    )

    if (-not (Test-SigmaAdmin)) {
        Write-SigmaLog 'A restore point needs administrator rights; skipping.' -Level Warn
        return $false
    }

    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Create restore point '$Description'")) {
        return $true
    }

    $gatePath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $gateName = 'SystemRestorePointCreationFrequency'
    $previousGate = Get-SigmaRegistryValue -Path $gatePath -Name $gateName

    try {
        Set-SigmaRegistryValue -Path $gatePath -Name $gateName -Type DWord -Value 0 -Confirm:$false | Out-Null

        Write-SigmaLog "Creating restore point '$Description' (this can take a minute)..." -Level Info
        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-SigmaLog "Restore point '$Description' created." -Level Success
        return $true
    } catch {
        Write-SigmaLog "Restore point failed: $($_.Exception.Message)" -Level Warn
        Write-SigmaLog 'Enable System Protection in Settings if you want restore points.' -Level Warn
        return $false
    } finally {
        if ($previousGate.Exists) {
            Set-SigmaRegistryValue -Path $gatePath -Name $gateName -Type DWord -Value $previousGate.Value -Confirm:$false | Out-Null
        } else {
            Remove-SigmaRegistryValue -Path $gatePath -Name $gateName -Confirm:$false | Out-Null
        }
    }
}

function New-SigmaSnapshotEntry {
    <#
    .SYNOPSIS
        Captures the current state of everything one tweak declares.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Tweak
    )

    $entries = New-Object System.Collections.ArrayList

    foreach ($item in @($Tweak.Registry)) {
        if (-not $item) { continue }
        $current = Get-SigmaRegistryValue -Path $item.Path -Name $item.Name
        [void]$entries.Add([pscustomobject]@{
            TweakId = $Tweak.Id
            Kind    = 'Registry'
            Path    = $current.Path
            Name    = $item.Name
            Existed = $current.Exists
            Value   = $current.Value
            Type    = $(if ($current.Type) { $current.Type.ToString() } else { $item.Type })
        })
    }

    foreach ($item in @($Tweak.Services)) {
        if (-not $item) { continue }
        $state = Get-SigmaServiceState -Name $item.Name
        [void]$entries.Add([pscustomobject]@{
            TweakId     = $Tweak.Id
            Kind        = 'Service'
            Name        = $item.Name
            Existed     = $state.Exists
            StartupType = $state.StartupType
            Status      = $state.Status
        })
    }

    foreach ($item in @($Tweak.ScheduledTasks)) {
        if (-not $item) { continue }
        $state = Get-SigmaScheduledTaskState -TaskPath $item.TaskPath -TaskName $item.TaskName
        [void]$entries.Add([pscustomobject]@{
            TweakId  = $Tweak.Id
            Kind     = 'ScheduledTask'
            TaskPath = $item.TaskPath
            TaskName = $item.TaskName
            Existed  = $state.Exists
            Enabled  = $state.Enabled
        })
    }

    return $entries.ToArray()
}

function New-SigmaBackup {
    <#
    .SYNOPSIS
        Writes a JSON snapshot for a set of tweaks and returns its path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]] $Tweaks,

        [string] $Label = 'apply'
    )

    $entries = New-Object System.Collections.ArrayList
    foreach ($tweak in $Tweaks) {
        foreach ($entry in (New-SigmaSnapshotEntry -Tweak $tweak)) {
            [void]$entries.Add($entry)
        }
    }

    if ($entries.Count -eq 0) {
        Write-SigmaLog 'Nothing to back up for the selected tweaks.' -Level Debug
        return $null
    }

    $backupDir = Get-SigmaDataPath -ChildPath 'backups'
    $file = Join-Path $backupDir ('{0}_{1}.json' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), $Label)

    $payload = [ordered]@{
        Version   = 1
        Created   = (Get-Date -Format 'o')
        Computer  = $env:COMPUTERNAME
        User      = $env:USERNAME
        Label     = $Label
        TweakIds  = @($Tweaks | Select-Object -ExpandProperty Id)
        Entries   = $entries.ToArray()
    }

    try {
        $payload | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $file -Encoding utf8 -ErrorAction Stop
        Write-SigmaLog "Backup written to $file" -Level Debug
        return $file
    } catch {
        Write-SigmaLog "Could not write backup: $($_.Exception.Message)" -Level Error
        return $null
    }
}

function Get-SigmaBackup {
    <#
    .SYNOPSIS
        Lists saved snapshots, newest first.
    #>
    [CmdletBinding()]
    param()

    $backupDir = Get-SigmaDataPath -ChildPath 'backups'
    Get-ChildItem -LiteralPath $backupDir -Filter '*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object {
            $data = $null
            try { $data = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json } catch { }
            [pscustomobject]@{
                Path       = $_.FullName
                FileName   = $_.Name
                Created    = $(if ($data) { $data.Created } else { $_.LastWriteTime.ToString('o') })
                Label      = $(if ($data) { $data.Label } else { 'unknown' })
                TweakCount = $(if ($data -and $data.TweakIds) { @($data.TweakIds).Count } else { 0 })
                EntryCount = $(if ($data -and $data.Entries) { @($data.Entries).Count } else { 0 })
            }
        }
}

function Restore-SigmaBackup {
    <#
    .SYNOPSIS
        Replays a snapshot, putting every captured value back as it was.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-SigmaLog "Backup file not found: $Path" -Level Error
        return $false
    }

    try {
        $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-SigmaLog "Backup file is not readable: $($_.Exception.Message)" -Level Error
        return $false
    }

    $restored = 0
    $failed = 0

    foreach ($entry in @($data.Entries)) {
        switch ($entry.Kind) {
            'Registry' {
                if ($entry.Existed) {
                    $value = $entry.Value
                    if ($entry.Type -eq 'Binary' -and $value -is [array]) {
                        $value = [byte[]]$value
                    }
                    $type = $(if ($entry.Type) { $entry.Type } else { 'String' })
                    $ok = Set-SigmaRegistryValue -Path $entry.Path -Name $entry.Name -Value $value -Type $type
                } else {
                    $ok = Remove-SigmaRegistryValue -Path $entry.Path -Name $entry.Name
                }
            }
            'Service' {
                if ($entry.Existed -and $entry.StartupType) {
                    $ok = Set-SigmaServiceStartup -Name $entry.Name -StartupType $entry.StartupType
                    if ($ok -and $entry.Status -eq 'Running') {
                        Start-SigmaService -Name $entry.Name | Out-Null
                    }
                } else {
                    $ok = $true
                }
            }
            'ScheduledTask' {
                if ($entry.Existed -and $null -ne $entry.Enabled) {
                    $ok = Set-SigmaScheduledTaskState -TaskPath $entry.TaskPath -TaskName $entry.TaskName -Enabled ([bool]$entry.Enabled)
                } else {
                    $ok = $true
                }
            }
            default { $ok = $true }
        }

        if ($ok) { $restored++ } else { $failed++ }
    }

    Write-SigmaLog "Restored $restored entries from $(Split-Path -Leaf $Path); $failed failed." -Level $(if ($failed) { 'Warn' } else { 'Success' })
    return ($failed -eq 0)
}
