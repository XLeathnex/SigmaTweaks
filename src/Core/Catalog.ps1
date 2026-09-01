<#
.SYNOPSIS
    Loads and indexes the tweak definitions in src/Tweaks.
.DESCRIPTION
    Each file under src/Tweaks emits an array of tweak hashtables when invoked.
    The catalog runs them, validates the results and caches the merged list.

    Tweak files run in their own scope, so any Apply/Revert/Test scriptblock
    inside them must be self-contained: call the Sigma* helper functions, but
    do not capture local variables from the defining file.
#>

$script:SigmaCatalog = $null
$script:SigmaActions = $null

# The order categories appear in the sidebar and in --list output.
$script:SigmaCategoryOrder = @(
    'Performance'
    'Gaming'
    'Privacy'
    'Network'
    'Explorer'
    'Services'
    'Updates'
    'Power'
    'Debloat'
)

function Get-SigmaTweakRoot {
    <#
    .SYNOPSIS
        Absolute path of the src/Tweaks directory.
    #>
    [CmdletBinding()]
    param()

    return (Join-Path $script:SigmaRoot 'src\Tweaks')
}

function Test-SigmaTweakDefinition {
    <#
    .SYNOPSIS
        Validates a single definition, returning the list of problems found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Tweak,
        [string] $Source = '<unknown>'
    )

    $problems = New-Object System.Collections.ArrayList

    if ($Tweak -isnot [hashtable]) {
        [void]$problems.Add("$Source contains a definition that is not a hashtable")
        return $problems.ToArray()
    }

    foreach ($required in @('Id', 'Name', 'Category', 'Description')) {
        if (-not $Tweak[$required]) {
            [void]$problems.Add("$Source : a tweak is missing '$required'")
        }
    }

    if ($Tweak.Risk -and $Tweak.Risk -notin @('Low', 'Medium', 'High')) {
        [void]$problems.Add("$($Tweak.Id): Risk must be Low, Medium or High")
    }

    $hasAction = $Tweak.Registry -or $Tweak.Services -or $Tweak.ScheduledTasks -or
                 $Tweak.Appx -or ($Tweak.Apply -is [scriptblock])
    if (-not $hasAction) {
        [void]$problems.Add("$($Tweak.Id): defines no registry, service, task, appx or Apply action")
    }

    foreach ($item in @($Tweak.Registry)) {
        if (-not $item) { continue }
        if (-not $item.Path -or $null -eq $item.Name) {
            [void]$problems.Add("$($Tweak.Id): a registry entry is missing Path or Name")
        }
        if (-not $Tweak.ContainsKey('Test') -and -not $item.ContainsKey('Default')) {
            [void]$problems.Add("$($Tweak.Id): registry entry '$($item.Name)' has no Default, so it cannot be reverted")
        }
    }

    return $problems.ToArray()
}

function Get-SigmaTweakCatalog {
    <#
    .SYNOPSIS
        Returns every tweak definition, loading them on first use.
    #>
    [CmdletBinding()]
    param(
        [switch] $Refresh
    )

    if ($script:SigmaCatalog -and -not $Refresh) {
        return $script:SigmaCatalog
    }

    $all = New-Object System.Collections.ArrayList
    $seen = @{}
    $root = Get-SigmaTweakRoot

    if (-not (Test-Path -LiteralPath $root)) {
        Write-SigmaLog "Tweak directory not found: $root" -Level Error
        $script:SigmaCatalog = @()
        return $script:SigmaCatalog
    }

    foreach ($file in (Get-ChildItem -LiteralPath $root -Filter '*.ps1' | Sort-Object Name)) {
        try {
            $definitions = @(& $file.FullName)
        } catch {
            Write-SigmaLog "Failed to load $($file.Name): $($_.Exception.Message)" -Level Error
            continue
        }

        foreach ($tweak in $definitions) {
            $problems = Test-SigmaTweakDefinition -Tweak $tweak -Source $file.Name
            if ($problems.Count -gt 0) {
                foreach ($problem in $problems) { Write-SigmaLog $problem -Level Warn }
                continue
            }

            if ($seen.ContainsKey($tweak.Id)) {
                Write-SigmaLog "Duplicate tweak id '$($tweak.Id)' in $($file.Name); keeping the first." -Level Warn
                continue
            }

            $seen[$tweak.Id] = $true
            if (-not $tweak.ContainsKey('Risk')) { $tweak.Risk = 'Low' }
            if (-not $tweak.ContainsKey('RequiresAdmin')) { $tweak.RequiresAdmin = $true }
            $tweak.Source = $file.Name
            [void]$all.Add($tweak)
        }
    }

    $script:SigmaCatalog = $all.ToArray()
    Write-SigmaLog "Loaded $($script:SigmaCatalog.Count) tweaks from $((Get-ChildItem -LiteralPath $root -Filter '*.ps1').Count) files." -Level Debug
    return $script:SigmaCatalog
}

function Get-SigmaTweakById {
    <#
    .SYNOPSIS
        Finds tweaks by exact id or by wildcard pattern.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $Id
    )

    $catalog = Get-SigmaTweakCatalog
    $matched = New-Object System.Collections.ArrayList

    foreach ($pattern in $Id) {
        $hits = @($catalog | Where-Object { $_.Id -eq $pattern })
        if ($hits.Count -eq 0 -and $pattern -match '[\*\?]') {
            $hits = @($catalog | Where-Object { $_.Id -like $pattern })
        }
        if ($hits.Count -eq 0) {
            Write-SigmaLog "No tweak matches '$pattern'." -Level Warn
            continue
        }
        foreach ($hit in $hits) {
            if (-not ($matched | Where-Object { $_.Id -eq $hit.Id })) {
                [void]$matched.Add($hit)
            }
        }
    }

    return $matched.ToArray()
}

function Get-SigmaCategory {
    <#
    .SYNOPSIS
        Category names in display order, including any not in the preferred list.
    #>
    [CmdletBinding()]
    param()

    $present = @(Get-SigmaTweakCatalog | Select-Object -ExpandProperty Category -Unique)
    $ordered = New-Object System.Collections.ArrayList

    foreach ($name in $script:SigmaCategoryOrder) {
        if ($present -contains $name) { [void]$ordered.Add($name) }
    }
    foreach ($name in ($present | Sort-Object)) {
        if (-not $ordered.Contains($name)) { [void]$ordered.Add($name) }
    }

    return $ordered.ToArray()
}

function Get-SigmaPreset {
    <#
    .SYNOPSIS
        Lists the presets shipped in the presets directory.
    #>
    [CmdletBinding()]
    param(
        [string] $Name
    )

    $presetDir = Join-Path $script:SigmaRoot 'presets'
    if (-not (Test-Path -LiteralPath $presetDir)) { return @() }

    $files = Get-ChildItem -LiteralPath $presetDir -Filter '*.json' | Sort-Object Name
    $presets = New-Object System.Collections.ArrayList

    foreach ($file in $files) {
        try {
            $data = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-SigmaLog "Preset $($file.Name) is not valid JSON: $($_.Exception.Message)" -Level Warn
            continue
        }

        [void]$presets.Add([pscustomobject]@{
            Name        = $(if ($data.Name) { $data.Name } else { [IO.Path]::GetFileNameWithoutExtension($file.Name) })
            Key         = [IO.Path]::GetFileNameWithoutExtension($file.Name)
            Description = $data.Description
            TweakIds    = @($data.Tweaks)
            Path        = $file.FullName
        })
    }

    if ($Name) {
        return @($presets | Where-Object { $_.Key -eq $Name -or $_.Name -eq $Name })
    }

    return $presets.ToArray()
}

function Export-SigmaProfile {
    <#
    .SYNOPSIS
        Saves the ids of every currently applied tweak to a JSON profile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $applied = New-Object System.Collections.ArrayList
    foreach ($tweak in (Get-SigmaTweakCatalog)) {
        if ((Test-SigmaTweak -Tweak $tweak) -eq 'Applied') {
            [void]$applied.Add($tweak.Id)
        }
    }

    $payload = [ordered]@{
        Name        = 'Exported profile'
        Description = "Captured on $(Get-Date -Format 'yyyy-MM-dd HH:mm') from $env:COMPUTERNAME"
        Tweaks      = $applied.ToArray()
    }

    try {
        $payload | ConvertTo-Json -Depth 4 | Out-File -LiteralPath $Path -Encoding utf8 -ErrorAction Stop
        Write-SigmaLog "Exported $($applied.Count) applied tweaks to $Path" -Level Success
        return $true
    } catch {
        Write-SigmaLog "Export failed: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Import-SigmaProfile {
    <#
    .SYNOPSIS
        Reads a profile or preset file and returns the matching tweaks.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-SigmaLog "Profile not found: $Path" -Level Error
        return @()
    }

    try {
        $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-SigmaLog "Profile is not valid JSON: $($_.Exception.Message)" -Level Error
        return @()
    }

    return Get-SigmaTweakById -Id @($data.Tweaks)
}

function Get-SigmaActionCatalog {
    <#
    .SYNOPSIS
        Returns the one-shot maintenance actions from src/Actions.
    #>
    [CmdletBinding()]
    param(
        [switch] $Refresh
    )

    if ($script:SigmaActions -and -not $Refresh) {
        return $script:SigmaActions
    }

    $all = New-Object System.Collections.ArrayList
    $root = Join-Path $script:SigmaRoot 'src\Actions'

    if (Test-Path -LiteralPath $root) {
        foreach ($file in (Get-ChildItem -LiteralPath $root -Filter '*.ps1' | Sort-Object Name)) {
            try {
                foreach ($action in @(& $file.FullName)) {
                    if ($action -isnot [hashtable] -or -not $action.Id -or $action.Run -isnot [scriptblock]) {
                        Write-SigmaLog "$($file.Name) contains an action without an Id or Run block." -Level Warn
                        continue
                    }
                    [void]$all.Add($action)
                }
            } catch {
                Write-SigmaLog "Failed to load $($file.Name): $($_.Exception.Message)" -Level Error
            }
        }
    }

    $script:SigmaActions = $all.ToArray()
    return $script:SigmaActions
}

function Invoke-SigmaAction {
    <#
    .SYNOPSIS
        Runs a maintenance action by id.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Id
    )

    $action = Get-SigmaActionCatalog | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $action) {
        Write-SigmaLog "No action with id '$Id'." -Level Error
        return $false
    }

    if (-not $PSCmdlet.ShouldProcess($action.Name, 'Run')) { return $true }

    Write-SigmaLog "Running: $($action.Name)" -Level Info
    try {
        $result = & $action.Run
        if ($result -is [bool] -and -not $result) {
            Write-SigmaLog "$($action.Name) reported a problem." -Level Warn
            return $false
        }
        return $true
    } catch {
        Write-SigmaLog "$($action.Name) failed: $($_.Exception.Message)" -Level Error
        return $false
    }
}
