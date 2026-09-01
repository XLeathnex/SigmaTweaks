<#
.SYNOPSIS
    Applies, reverts and inspects tweaks.
.DESCRIPTION
    A tweak is a hashtable. Most of them are fully declarative: they list the
    registry values, services and scheduled tasks they change, and the engine
    derives apply, revert and state-detection behaviour from that list. Tweaks
    that cannot be expressed declaratively supply Apply/Revert/Test
    scriptblocks instead, and the engine treats those as authoritative.

    Tweak schema
    ------------
    Id             Unique dotted identifier, e.g. 'privacy.telemetry'.
    Name           Short label shown in the UI.
    Category       Category name; drives the sidebar.
    Description    One or two sentences explaining what changes and why.
    Risk           Low | Medium | High.
    RequiresAdmin  Defaults to $true.
    RequiresRestart Whether the change needs a reboot or Explorer restart.
    RestartExplorer Restart Explorer after applying.
    Recommended    Included by presets that ask for recommended tweaks.
    Irreversible   Apply cannot be undone by SigmaTweaks (Store app removal).
    Requires       Hashtable: MinBuild, Windows11, Ssd.
    Registry       Array of @{ Path; Name; Type; Value; Default }.
    Services       Array of @{ Name; StartupType; Default; Stop }.
    ScheduledTasks Array of @{ TaskPath; TaskName }.
    Appx           Array of @{ PackageName; WingetId }.
    Apply/Revert   Optional scriptblocks returning $true on success.
    Test           Optional scriptblock returning $true when applied.
#>

function New-SigmaResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Tweak,
        [Parameter(Mandatory)] [ValidateSet('Apply', 'Revert')] [string] $Mode,
        [bool] $Success = $true,
        [bool] $Changed = $false,
        [string] $Message = ''
    )

    return [pscustomobject]@{
        Id      = $Tweak.Id
        Name    = $Tweak.Name
        Mode    = $Mode
        Success = $Success
        Changed = $Changed
        Message = $Message
    }
}

function Test-SigmaTweakApplicable {
    <#
    .SYNOPSIS
        Decides whether a tweak makes sense on this machine.
    .OUTPUTS
        PSCustomObject with Applicable and Reason.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Tweak,
        $SystemInfo
    )

    if (-not $Tweak.Requires) {
        return [pscustomobject]@{ Applicable = $true; Reason = '' }
    }

    if (-not $SystemInfo) { $SystemInfo = Get-SigmaSystemInfo }

    if ($Tweak.Requires.Windows11 -and -not $SystemInfo.IsWindows11) {
        return [pscustomobject]@{ Applicable = $false; Reason = 'Windows 11 only' }
    }

    if ($Tweak.Requires.MinBuild) {
        $build = 0
        [void][int]::TryParse("$($SystemInfo.Build)", [ref]$build)
        if ($build -gt 0 -and $build -lt [int]$Tweak.Requires.MinBuild) {
            return [pscustomobject]@{ Applicable = $false; Reason = "Needs build $($Tweak.Requires.MinBuild) or newer" }
        }
    }

    if ($Tweak.Requires.Ssd) {
        $isSsd = Test-SigmaSsd
        if ($isSsd -eq $false) {
            return [pscustomobject]@{ Applicable = $false; Reason = 'Only useful on an SSD' }
        }
    }

    return [pscustomobject]@{ Applicable = $true; Reason = '' }
}

function Test-SigmaTweak {
    <#
    .SYNOPSIS
        Reports whether a tweak is currently applied.
    .OUTPUTS
        'Applied', 'NotApplied', 'Partial' or 'Unknown'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Tweak
    )

    if ($Tweak.Test -is [scriptblock]) {
        try {
            $result = & $Tweak.Test
            if ($result -is [string]) { return $result }
            return $(if ($result) { 'Applied' } else { 'NotApplied' })
        } catch {
            Write-SigmaLog "State test for '$($Tweak.Id)' failed: $($_.Exception.Message)" -Level Debug
            return 'Unknown'
        }
    }

    $checks = New-Object System.Collections.ArrayList

    foreach ($item in @($Tweak.Registry)) {
        if (-not $item) { continue }
        [void]$checks.Add((Test-SigmaRegistryValue -Path $item.Path -Name $item.Name -Expected $item.Value))
    }

    foreach ($item in @($Tweak.Services)) {
        if (-not $item) { continue }
        $state = Get-SigmaServiceState -Name $item.Name
        # A service that does not exist on this edition cannot be off-target.
        if (-not $state.Exists) { continue }
        [void]$checks.Add($state.StartupType -eq $item.StartupType)
    }

    foreach ($item in @($Tweak.ScheduledTasks)) {
        if (-not $item) { continue }
        $state = Get-SigmaScheduledTaskState -TaskPath $item.TaskPath -TaskName $item.TaskName
        if (-not $state.Exists) { continue }
        [void]$checks.Add(-not $state.Enabled)
    }

    foreach ($item in @($Tweak.Appx)) {
        if (-not $item) { continue }
        $state = Get-SigmaAppxState -PackageName $item.PackageName
        [void]$checks.Add(-not ($state.Installed -or $state.Provisioned))
    }

    if ($checks.Count -eq 0) { return 'Unknown' }

    $applied = @($checks | Where-Object { $_ }).Count
    if ($applied -eq $checks.Count) { return 'Applied' }
    if ($applied -eq 0) { return 'NotApplied' }
    return 'Partial'
}

function Invoke-SigmaTweak {
    <#
    .SYNOPSIS
        Applies or reverts a single tweak.
    .PARAMETER Mode
        Apply writes the tweak's values; Revert writes the declared defaults.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] $Tweak,

        [Parameter(Mandatory)]
        [ValidateSet('Apply', 'Revert')]
        [string] $Mode
    )

    $requiresAdmin = $true
    if ($Tweak.ContainsKey('RequiresAdmin')) { $requiresAdmin = [bool]$Tweak.RequiresAdmin }

    if ($requiresAdmin -and -not (Test-SigmaAdmin)) {
        return New-SigmaResult -Tweak $Tweak -Mode $Mode -Success $false -Message 'Requires administrator rights'
    }

    if ($Mode -eq 'Revert' -and $Tweak.Irreversible -and -not ($Tweak.Revert -is [scriptblock])) {
        return New-SigmaResult -Tweak $Tweak -Mode $Mode -Success $false -Message 'This change cannot be undone automatically'
    }

    $target = '{0} ({1})' -f $Tweak.Name, $Tweak.Id
    if (-not $PSCmdlet.ShouldProcess($target, $Mode)) {
        return New-SigmaResult -Tweak $Tweak -Mode $Mode -Success $true -Changed $false -Message 'WhatIf'
    }

    $ok = $true
    $touched = $false

    foreach ($item in @($Tweak.Registry)) {
        if (-not $item) { continue }
        $desired = $(if ($Mode -eq 'Apply') { $item.Value } else { $item.Default })
        $type = $(if ($item.Type) { $item.Type } else { 'DWord' })

        if ($null -eq $desired) {
            $ok = (Remove-SigmaRegistryValue -Path $item.Path -Name $item.Name) -and $ok
        } else {
            $ok = (Set-SigmaRegistryValue -Path $item.Path -Name $item.Name -Value $desired -Type $type) -and $ok
        }
        $touched = $true
    }

    foreach ($item in @($Tweak.Services)) {
        if (-not $item) { continue }
        $desired = $(if ($Mode -eq 'Apply') { $item.StartupType } else { $item.Default })
        if (-not $desired) { continue }

        $stop = ($Mode -eq 'Apply' -and $item.Stop)
        $ok = (Set-SigmaServiceStartup -Name $item.Name -StartupType $desired -StopService:$stop) -and $ok

        if ($Mode -eq 'Revert' -and $desired -eq 'Automatic') {
            Start-SigmaService -Name $item.Name | Out-Null
        }
        $touched = $true
    }

    foreach ($item in @($Tweak.ScheduledTasks)) {
        if (-not $item) { continue }
        $enabled = ($Mode -eq 'Revert')
        $ok = (Set-SigmaScheduledTaskState -TaskPath $item.TaskPath -TaskName $item.TaskName -Enabled $enabled) -and $ok
        $touched = $true
    }

    foreach ($item in @($Tweak.Appx)) {
        if (-not $item) { continue }
        if ($Mode -eq 'Apply') {
            $ok = (Remove-SigmaAppx -PackageName $item.PackageName) -and $ok
        } else {
            $ok = (Install-SigmaAppx -PackageName $item.PackageName -WingetId $item.WingetId) -and $ok
        }
        $touched = $true
    }

    $custom = $(if ($Mode -eq 'Apply') { $Tweak.Apply } else { $Tweak.Revert })
    if ($custom -is [scriptblock]) {
        try {
            $result = & $custom
            if ($result -is [bool]) { $ok = $result -and $ok }
            $touched = $true
        } catch {
            Write-SigmaLog "$Mode of '$($Tweak.Id)' threw: $($_.Exception.Message)" -Level Error
            $ok = $false
        }
    }

    if (-not $touched) {
        return New-SigmaResult -Tweak $Tweak -Mode $Mode -Success $false -Message 'Tweak defines no actions'
    }

    $message = $(if ($ok) { "$Mode completed" } else { "$Mode completed with errors" })
    return New-SigmaResult -Tweak $Tweak -Mode $Mode -Success $ok -Changed $ok -Message $message
}

function Invoke-SigmaTweakSet {
    <#
    .SYNOPSIS
        Applies or reverts many tweaks, taking one backup for the whole batch.
    .PARAMETER SkipBackup
        Skip the JSON snapshot. Reverting already replays declared defaults, so
        the GUI uses this for revert batches that came from a backup.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [object[]] $Tweaks,

        [Parameter(Mandatory)]
        [ValidateSet('Apply', 'Revert')]
        [string] $Mode,

        [switch] $SkipBackup,

        [switch] $CreateRestorePoint
    )

    $results = New-Object System.Collections.ArrayList

    if ($Tweaks.Count -eq 0) {
        Write-SigmaLog 'No tweaks selected.' -Level Warn
        return $results.ToArray()
    }

    Write-SigmaLog "$Mode`ing $($Tweaks.Count) tweak(s)..." -Level Info

    if ($CreateRestorePoint -and -not $WhatIfPreference) {
        New-SigmaRestorePoint -Description "SigmaTweaks $Mode" | Out-Null
    }

    if (-not $SkipBackup -and -not $WhatIfPreference) {
        $backup = New-SigmaBackup -Tweaks $Tweaks -Label $Mode.ToLowerInvariant()
        if ($backup) { Write-SigmaLog "Previous state saved to $(Split-Path -Leaf $backup)" -Level Info }
    }

    $needsRestart = $false
    $needsExplorer = $false

    foreach ($tweak in $Tweaks) {
        $result = Invoke-SigmaTweak -Tweak $tweak -Mode $Mode
        [void]$results.Add($result)

        if ($result.Success) {
            Write-SigmaLog "  [ok]   $($tweak.Name)" -Level Success
            if ($tweak.RequiresRestart) { $needsRestart = $true }
            if ($tweak.RestartExplorer) { $needsExplorer = $true }
        } else {
            Write-SigmaLog "  [fail] $($tweak.Name) - $($result.Message)" -Level Error
        }
    }

    if ($needsExplorer -and -not $WhatIfPreference) {
        Restart-SigmaExplorer
    }

    $succeeded = @($results | Where-Object { $_.Success }).Count
    $failed = $results.Count - $succeeded
    Write-SigmaLog "$Mode finished: $succeeded succeeded, $failed failed." -Level $(if ($failed) { 'Warn' } else { 'Success' })

    if ($needsRestart) {
        Write-SigmaLog 'Some changes only take effect after a restart.' -Level Warn
    }

    return $results.ToArray()
}

function Restart-SigmaExplorer {
    <#
    .SYNOPSIS
        Restarts explorer.exe so shell tweaks take effect immediately.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if (-not $PSCmdlet.ShouldProcess('explorer.exe', 'Restart')) { return }

    try {
        Write-SigmaLog 'Restarting Explorer...' -Level Info
        Stop-Process -Name 'explorer' -Force -ErrorAction Stop
        Start-Sleep -Milliseconds 800
        if (-not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) {
            Start-Process -FilePath 'explorer.exe'
        }
    } catch {
        Write-SigmaLog "Could not restart Explorer: $($_.Exception.Message)" -Level Warn
    }
}
