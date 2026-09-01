<#
.SYNOPSIS
    Windows service and scheduled task helpers.
#>

$script:SigmaServiceStartValues = @{
    'Boot'      = 0
    'System'    = 1
    'Automatic' = 2
    'Manual'    = 3
    'Disabled'  = 4
}

# Services that SigmaTweaks will never reconfigure, because losing them breaks
# networking, logon, updates or security in ways a "revert" cannot undo.
$script:SigmaProtectedServices = @(
    'BFE', 'Dhcp', 'Dnscache', 'EventLog', 'gpsvc', 'LanmanWorkstation',
    'mpssvc', 'NlaSvc', 'nsi', 'PlugPlay', 'Power', 'ProfSvc', 'RpcEptMapper',
    'RpcSs', 'SamSs', 'Schedule', 'SecurityHealthService', 'Sense', 'TrustedInstaller',
    'UserManager', 'WdNisSvc', 'WinDefend', 'Winmgmt', 'wscsvc', 'wuauserv'
)

function Test-SigmaProtectedService {
    <#
    .SYNOPSIS
        True when a service is on the never-touch list.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    return ($script:SigmaProtectedServices -contains $Name)
}

function Get-SigmaServiceState {
    <#
    .SYNOPSIS
        Reports whether a service exists and how it is currently configured.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $state = [ordered]@{
        Name        = $Name
        Exists      = $false
        Status      = $null
        StartupType = $null
    }

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return [pscustomobject]$state }

    $state.Exists = $true
    $state.Status = $svc.Status.ToString()

    # Read the raw Start value: Get-Service in Windows PowerShell 5.1 has no
    # StartType property, and the registry is authoritative either way.
    $reg = Get-SigmaRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -Name 'Start'
    if ($reg.Exists) {
        $match = $script:SigmaServiceStartValues.GetEnumerator() |
            Where-Object { $_.Value -eq [int]$reg.Value } | Select-Object -First 1
        if ($match) { $state.StartupType = $match.Key }
    }

    return [pscustomobject]$state
}

function Set-SigmaServiceStartup {
    <#
    .SYNOPSIS
        Sets a service's startup type, optionally stopping it as well.
    .DESCRIPTION
        Tries Set-Service first and falls back to writing the Start value
        directly, which succeeds for services whose SCM ACL denies changes to
        an elevated administrator (DiagTrack is the usual example).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateSet('Automatic', 'Manual', 'Disabled')]
        [string] $StartupType,

        [switch] $StopService
    )

    if (Test-SigmaProtectedService -Name $Name) {
        Write-SigmaLog "Refusing to reconfigure protected service '$Name'." -Level Warn
        return $false
    }

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-SigmaLog "Service '$Name' is not installed; skipping." -Level Debug
        return $true
    }

    if (-not $PSCmdlet.ShouldProcess($Name, "Set startup type to $StartupType")) {
        return $true
    }

    $ok = $true

    if ($StopService -and $svc.Status -ne 'Stopped') {
        try {
            Stop-Service -Name $Name -Force -ErrorAction Stop
            Write-SigmaLog "Stopped service '$Name'." -Level Debug
        } catch {
            Write-SigmaLog "Could not stop '$Name': $($_.Exception.Message)" -Level Warn
        }
    }

    try {
        Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
    } catch {
        Write-SigmaLog "Set-Service failed for '$Name', falling back to registry." -Level Debug
        $ok = Set-SigmaRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" `
            -Name 'Start' -Type DWord -Value $script:SigmaServiceStartValues[$StartupType]
    }

    if ($ok) {
        Write-SigmaLog "Service '$Name' startup type set to $StartupType." -Level Debug
    }
    return $ok
}

function Start-SigmaService {
    <#
    .SYNOPSIS
        Starts a service, ignoring services that are absent.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc -or $svc.Status -eq 'Running') { return $true }

    if (-not $PSCmdlet.ShouldProcess($Name, 'Start service')) { return $true }

    try {
        Start-Service -Name $Name -ErrorAction Stop
        return $true
    } catch {
        Write-SigmaLog "Could not start '$Name': $($_.Exception.Message)" -Level Warn
        return $false
    }
}

function Get-SigmaScheduledTaskState {
    <#
    .SYNOPSIS
        Returns Exists/Enabled for a scheduled task given its full path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $TaskPath,

        [Parameter(Mandatory)]
        [string] $TaskName
    )

    $state = [ordered]@{ TaskPath = $TaskPath; TaskName = $TaskName; Exists = $false; Enabled = $null }

    try {
        $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop
        $state.Exists = $true
        $state.Enabled = ($task.State -ne 'Disabled')
    } catch {
        # Task is not present on this edition or build.
    }

    return [pscustomobject]$state
}

function Set-SigmaScheduledTaskState {
    <#
    .SYNOPSIS
        Enables or disables a scheduled task by full path.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $TaskPath,

        [Parameter(Mandatory)]
        [string] $TaskName,

        [Parameter(Mandatory)]
        [bool] $Enabled
    )

    $full = ($TaskPath.TrimEnd('\') + '\' + $TaskName)
    $action = $(if ($Enabled) { 'Enable' } else { 'Disable' })

    if (-not $PSCmdlet.ShouldProcess($full, "$action scheduled task")) { return $true }

    try {
        if ($Enabled) {
            Enable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
        } else {
            Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
        }
        Write-SigmaLog "$action`d scheduled task $full" -Level Debug
        return $true
    } catch {
        Write-SigmaLog "Scheduled task $full not found or not changeable." -Level Debug
        # A missing task is not a failure: builds differ in which tasks ship.
        return $true
    }
}
