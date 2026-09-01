<#
.SYNOPSIS
    Host environment discovery and privilege handling.
#>

function Test-SigmaAdmin {
    <#
    .SYNOPSIS
        True when the current process holds the local Administrators role.
    #>
    [CmdletBinding()]
    param()

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Test-SigmaWindows {
    <#
    .SYNOPSIS
        True when running on Windows. SigmaTweaks refuses to touch anything else.
    #>
    [CmdletBinding()]
    param()

    if ($null -ne $PSVersionTable.Platform -and $PSVersionTable.Platform -ne 'Win32NT') {
        return $false
    }
    return $true
}

function Get-SigmaSystemInfo {
    <#
    .SYNOPSIS
        Collects the host facts shown in the GUI header and the system report.
    #>
    [CmdletBinding()]
    param()

    $info = [ordered]@{
        ComputerName   = $env:COMPUTERNAME
        UserName       = $env:USERNAME
        OSName         = 'Unknown'
        OSVersion      = 'Unknown'
        Build          = 'Unknown'
        Edition        = 'Unknown'
        Architecture   = $env:PROCESSOR_ARCHITECTURE
        CPU            = 'Unknown'
        MemoryGB       = 0
        GPU            = 'Unknown'
        SystemDrive    = $env:SystemDrive
        SystemDriveType = 'Unknown'
        FreeSpaceGB    = 0
        PowerShell     = $PSVersionTable.PSVersion.ToString()
        IsAdmin        = (Test-SigmaAdmin)
        IsWindows11    = $false
    }

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $info.OSName = $os.Caption
        $info.OSVersion = $os.Version
        $info.Build = $os.BuildNumber
        $info.MemoryGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        # Windows 11 reports itself as 10.0 but always carries build 22000+.
        $info.IsWindows11 = ([int]$os.BuildNumber -ge 22000)
    } catch {
        Write-SigmaLog "Unable to query Win32_OperatingSystem: $($_.Exception.Message)" -Level Debug
    }

    try {
        $info.Edition = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop).EditionID
        $display = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).DisplayVersion
        if ($display) { $info.OSVersion = '{0} ({1})' -f $info.OSVersion, $display }
    } catch {
        Write-SigmaLog "Unable to read CurrentVersion key: $($_.Exception.Message)" -Level Debug
    }

    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $info.CPU = '{0} ({1}C/{2}T)' -f $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors
    } catch { }

    try {
        $gpus = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.Name } | Select-Object -ExpandProperty Name
        if ($gpus) { $info.GPU = ($gpus -join ', ') }
    } catch { }

    try {
        $drive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction Stop
        $info.FreeSpaceGB = [math]::Round($drive.FreeSpace / 1GB, 1)
    } catch { }

    try {
        $physical = Get-PhysicalDisk -ErrorAction Stop | Select-Object -First 1
        if ($physical) { $info.SystemDriveType = $physical.MediaType }
    } catch {
        # Get-PhysicalDisk is unavailable on some editions; not worth surfacing.
    }

    return [pscustomobject]$info
}

function Test-SigmaSsd {
    <#
    .SYNOPSIS
        True when the system disk reports itself as solid state.
    .DESCRIPTION
        Used to tag tweaks that only make sense on SSDs (Prefetch, SysMain).
        Returns $null when the media type cannot be determined.
    #>
    [CmdletBinding()]
    param()

    try {
        $disks = Get-PhysicalDisk -ErrorAction Stop
        if (-not $disks) { return $null }
        if ($disks | Where-Object { $_.MediaType -eq 'SSD' }) { return $true }
        if ($disks | Where-Object { $_.MediaType -eq 'HDD' }) { return $false }
        return $null
    } catch {
        return $null
    }
}

function Invoke-SigmaElevation {
    <#
    .SYNOPSIS
        Relaunches the entry script elevated, forwarding the original arguments.
    .OUTPUTS
        $true when a new elevated process was started (the caller should exit).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ScriptPath,

        [string[]] $Arguments = @()
    )

    $psExe = (Get-Process -Id $PID).Path
    if (-not $psExe) { $psExe = 'powershell.exe' }

    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $ScriptPath)) + $Arguments

    try {
        Start-Process -FilePath $psExe -ArgumentList $argList -Verb RunAs -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-SigmaLog "Elevation was declined or failed: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Request-SigmaRestart {
    <#
    .SYNOPSIS
        Asks the user to restart and performs it when confirmed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [int] $DelaySeconds = 10
    )

    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Restart computer')) {
        Write-SigmaLog "Restarting in $DelaySeconds seconds..." -Level Warn
        Start-Process -FilePath 'shutdown.exe' -ArgumentList @('/r', '/t', $DelaySeconds, '/c', 'Restart requested by SigmaTweaks') -WindowStyle Hidden
    }
}
