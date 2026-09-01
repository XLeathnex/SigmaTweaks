<#
.SYNOPSIS
    SigmaTweaks - a Windows 11 optimization and debloat tool.

.DESCRIPTION
    Run with no arguments for the graphical interface. The switches below drive
    the same engine from a script or a scheduled task.

    Nothing here disables Microsoft Defender, SmartScreen, UAC or the Windows
    Firewall, and nothing turns Windows Update off. Every setting change is
    recorded to a JSON snapshot before it is made, and can be reverted.

.PARAMETER List
    Print the tweak catalog and exit.

.PARAMETER Status
    Print each tweak with its current state (applied, off, partial).

.PARAMETER Apply
    Tweak ids to apply. Wildcards are allowed, e.g. -Apply 'privacy.*'.

.PARAMETER Revert
    Tweak ids to revert, same matching rules as -Apply.

.PARAMETER Preset
    Apply a preset from the presets directory, e.g. -Preset recommended.

.PARAMETER ImportProfile
    Apply the tweak ids listed in a JSON profile file.

.PARAMETER ExportProfile
    Write every currently applied tweak id to a JSON profile and exit.

.PARAMETER RunAction
    Run a maintenance action by id, e.g. -RunAction action.cleantemp.

.PARAMETER ListBackups
    Print saved snapshots and exit.

.PARAMETER RestoreBackup
    Replay a snapshot file, putting the recorded values back.

.PARAMETER RestorePoint
    Create a system restore point before applying anything.

.PARAMETER NoElevate
    Do not relaunch elevated. Tweaks needing administrator rights will fail.

.EXAMPLE
    .\SigmaTweaks.ps1
    Opens the graphical interface.

.EXAMPLE
    .\SigmaTweaks.ps1 -Preset recommended -RestorePoint
    Applies the recommended preset after taking a restore point.

.EXAMPLE
    .\SigmaTweaks.ps1 -Apply 'privacy.*' -WhatIf
    Shows what applying every privacy tweak would change, without changing it.

.LINK
    https://github.com/XLeathnex/SigmaTweaks
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch] $List,
    [switch] $Status,
    [string[]] $Apply,
    [string[]] $Revert,
    [string] $Preset,
    [string] $ImportProfile,
    [string] $ExportProfile,
    [switch] $ListPresets,
    [switch] $ListActions,
    [string] $RunAction,
    [switch] $ListBackups,
    [string] $RestoreBackup,
    [switch] $RestorePoint,
    [switch] $NoElevate,
    [switch] $NoGui,
    [switch] $Quiet
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

$script:SigmaRoot = $PSScriptRoot
$script:SigmaVersion = '1.0.0'
$script:SigmaQuiet = [bool]$Quiet
$script:SigmaVerbose = ($VerbosePreference -ne 'SilentlyContinue')

# Core first: everything else calls into it. UI last: it calls into everything.
$loadOrder = @(
    'src\Core\Logging.ps1'
    'src\Core\Environment.ps1'
    'src\Core\Registry.ps1'
    'src\Core\Services.ps1'
    'src\Core\Appx.ps1'
    'src\Core\Backup.ps1'
    'src\Core\TweakEngine.ps1'
    'src\Core\Catalog.ps1'
    'src\UI\Gui.ps1'
)

foreach ($relative in $loadOrder) {
    $path = Join-Path $script:SigmaRoot $relative
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Error "SigmaTweaks is incomplete: $relative is missing."
        exit 1
    }
    . $path
}

Initialize-SigmaLog | Out-Null

if (-not (Test-SigmaWindows)) {
    Write-SigmaLog 'SigmaTweaks only runs on Windows.' -Level Error
    exit 1
}

Initialize-SigmaRegistryDrives

function Write-SigmaBanner {
    if ($script:SigmaQuiet) { return }

    $lines = @(
        ''
        '  ####  #  ####  #    #   #    ##',
        '  #     #  #     ##  ##  # #  #  #   SigmaTweaks ' + $script:SigmaVersion
        '  ####  #  # ##  # ## # #   # ####   Windows 11 optimization'
        '     #  #  #  #  #    # #   # #  #'
        '  ####  #  ####  #    # #   # #  #'
        ''
    )
    foreach ($line in $lines) { Write-Host $line -ForegroundColor Magenta }
}

function Show-SigmaCatalogList {
    <#
    .SYNOPSIS
        Prints the catalog grouped by category, optionally with live state.
    #>
    param([switch] $WithState)

    $info = Get-SigmaSystemInfo

    foreach ($category in (Get-SigmaCategory)) {
        Write-Host ''
        Write-Host "  $category" -ForegroundColor Cyan
        Write-Host ('  ' + ('-' * $category.Length)) -ForegroundColor DarkGray

        foreach ($tweak in (Get-SigmaTweakCatalog | Where-Object { $_.Category -eq $category })) {
            $state = ''
            if ($WithState) {
                $applicable = Test-SigmaTweakApplicable -Tweak $tweak -SystemInfo $info
                $state = $(if ($applicable.Applicable) { Test-SigmaTweak -Tweak $tweak } else { 'N/A' })
            }

            $colour = switch ($state) {
                'Applied' { 'Green' }
                'Partial' { 'Yellow' }
                'N/A'     { 'DarkGray' }
                default   { 'Gray' }
            }

            $line = '    {0,-38} {1,-8} {2}' -f $tweak.Id, $tweak.Risk, $tweak.Name
            if ($WithState) { $line = '    {0,-11} {1,-38} {2}' -f "[$state]", $tweak.Id, $tweak.Name }
            Write-Host $line -ForegroundColor $colour
        }
    }
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Read-only modes: no elevation needed, so handle them before asking for it.
# ---------------------------------------------------------------------------

if ($List) {
    Write-SigmaBanner
    Show-SigmaCatalogList
    exit 0
}

if ($ListPresets) {
    Write-SigmaBanner
    foreach ($preset in (Get-SigmaPreset)) {
        Write-Host ''
        Write-Host ('  {0}  ({1} tweaks)' -f $preset.Name, @($preset.TweakIds).Count) -ForegroundColor Cyan
        Write-Host ('    key: {0}' -f $preset.Key) -ForegroundColor DarkGray
        Write-Host ('    {0}' -f $preset.Description) -ForegroundColor Gray
    }
    Write-Host ''
    exit 0
}

if ($ListActions) {
    Write-SigmaBanner
    foreach ($action in (Get-SigmaActionCatalog)) {
        Write-Host ('  {0,-28} {1}' -f $action.Id, $action.Name) -ForegroundColor Gray
    }
    Write-Host ''
    exit 0
}

if ($ListBackups) {
    Write-SigmaBanner
    $backups = @(Get-SigmaBackup)
    if ($backups.Count -eq 0) {
        Write-Host '  No backups have been taken yet.' -ForegroundColor Gray
    } else {
        $backups | Format-Table -AutoSize Created, Label, TweakCount, EntryCount, FileName | Out-String | Write-Host
    }
    exit 0
}

if ($ExportProfile) {
    Write-SigmaBanner
    $ok = Export-SigmaProfile -Path $ExportProfile
    exit $(if ($ok) { 0 } else { 1 })
}

# ---------------------------------------------------------------------------
# Everything below changes the machine and needs administrator rights.
# ---------------------------------------------------------------------------

if (-not (Test-SigmaAdmin) -and -not $NoElevate -and -not $WhatIfPreference) {
    Write-SigmaLog 'Administrator rights are required; requesting elevation...' -Level Info

    $forward = New-Object System.Collections.ArrayList
    foreach ($name in $PSBoundParameters.Keys) {
        $value = $PSBoundParameters[$name]
        if ($value -is [switch]) {
            if ($value.IsPresent) { [void]$forward.Add("-$name") }
        } elseif ($value -is [array]) {
            [void]$forward.Add("-$name")
            [void]$forward.Add(($value -join ','))
        } else {
            [void]$forward.Add("-$name")
            [void]$forward.Add(('"{0}"' -f $value))
        }
    }

    if (Invoke-SigmaElevation -ScriptPath $PSCommandPath -Arguments $forward.ToArray()) {
        exit 0
    }

    Write-SigmaLog 'Continuing without elevation. Most tweaks will be refused.' -Level Warn
}

if ($Status) {
    Write-SigmaBanner
    Show-SigmaCatalogList -WithState
    exit 0
}

if ($RestoreBackup) {
    Write-SigmaBanner
    $ok = Restore-SigmaBackup -Path $RestoreBackup
    exit $(if ($ok) { 0 } else { 1 })
}

if ($RunAction) {
    Write-SigmaBanner
    $ok = Invoke-SigmaAction -Id $RunAction
    exit $(if ($ok) { 0 } else { 1 })
}

$batch = New-Object System.Collections.ArrayList
$batchMode = $null

if ($Preset) {
    $found = @(Get-SigmaPreset -Name $Preset) | Select-Object -First 1
    if (-not $found) {
        Write-SigmaLog "No preset named '$Preset'. Use -ListPresets to see them." -Level Error
        exit 1
    }
    Write-SigmaLog "Preset '$($found.Name)': $($found.Description)" -Level Info
    foreach ($tweak in (Get-SigmaTweakById -Id $found.TweakIds)) { [void]$batch.Add($tweak) }
    $batchMode = 'Apply'
}

if ($ImportProfile) {
    foreach ($tweak in (Import-SigmaProfile -Path $ImportProfile)) { [void]$batch.Add($tweak) }
    $batchMode = 'Apply'
}

if ($Apply) {
    foreach ($tweak in (Get-SigmaTweakById -Id $Apply)) { [void]$batch.Add($tweak) }
    $batchMode = 'Apply'
}

if ($Revert) {
    if ($batchMode -eq 'Apply') {
        Write-SigmaLog 'Use -Apply and -Revert in separate runs, not together.' -Level Error
        exit 1
    }
    foreach ($tweak in (Get-SigmaTweakById -Id $Revert)) { [void]$batch.Add($tweak) }
    $batchMode = 'Revert'
}

if ($batchMode) {
    Write-SigmaBanner

    $info = Get-SigmaSystemInfo
    $runnable = New-Object System.Collections.ArrayList
    foreach ($tweak in $batch) {
        $applicable = Test-SigmaTweakApplicable -Tweak $tweak -SystemInfo $info
        if ($applicable.Applicable) {
            [void]$runnable.Add($tweak)
        } else {
            Write-SigmaLog "Skipping $($tweak.Id): $($applicable.Reason)." -Level Info
        }
    }

    if ($runnable.Count -eq 0) {
        Write-SigmaLog 'Nothing to do.' -Level Warn
        exit 0
    }

    $results = Invoke-SigmaTweakSet -Tweaks $runnable.ToArray() -Mode $batchMode -CreateRestorePoint:$RestorePoint
    $failed = @($results | Where-Object { -not $_.Success }).Count
    exit $(if ($failed -gt 0) { 1 } else { 0 })
}

if ($NoGui) {
    Write-SigmaBanner
    Write-Host '  Nothing to do. Try -List, -Status, -Preset <name> or run without -NoGui.' -ForegroundColor Gray
    Write-Host '  Full help: Get-Help .\SigmaTweaks.ps1 -Detailed' -ForegroundColor DarkGray
    Write-Host ''
    exit 0
}

try {
    Show-SigmaGui
} catch {
    Write-SigmaLog "The interface failed to start: $($_.Exception.Message)" -Level Error
    Write-SigmaLog 'Use -NoGui with -List, -Status or -Preset to work from the console instead.' -Level Info
    exit 1
}
