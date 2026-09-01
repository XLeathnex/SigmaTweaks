<#
.SYNOPSIS
    Logging facilities for SigmaTweaks.
.DESCRIPTION
    Writes timestamped entries to a rolling log file under the SigmaTweaks data
    directory and mirrors them to the console and (when the GUI is running) to
    the in-app log pane via a registered sink.
#>

$script:SigmaLogSinks = New-Object System.Collections.ArrayList
$script:SigmaLogFile = $null

function Get-SigmaDataPath {
    <#
    .SYNOPSIS
        Returns the per-user data directory, creating it when missing.
    #>
    [CmdletBinding()]
    param(
        [string] $ChildPath
    )

    $root = Join-Path $env:LOCALAPPDATA 'SigmaTweaks'
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -Path $root -ItemType Directory -Force | Out-Null
    }

    if ($ChildPath) {
        $full = Join-Path $root $ChildPath
        if (-not (Test-Path -LiteralPath $full)) {
            New-Item -Path $full -ItemType Directory -Force | Out-Null
        }
        return $full
    }

    return $root
}

function Initialize-SigmaLog {
    <#
    .SYNOPSIS
        Opens a new log file for this session and prunes old ones.
    #>
    [CmdletBinding()]
    param(
        [int] $KeepFiles = 10
    )

    $logDir = Get-SigmaDataPath -ChildPath 'logs'
    $script:SigmaLogFile = Join-Path $logDir ('sigmatweaks_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

    "SigmaTweaks log started $(Get-Date -Format 'u')" | Out-File -LiteralPath $script:SigmaLogFile -Encoding utf8

    Get-ChildItem -LiteralPath $logDir -Filter 'sigmatweaks_*.log' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $KeepFiles |
        Remove-Item -Force -ErrorAction SilentlyContinue

    return $script:SigmaLogFile
}

function Register-SigmaLogSink {
    <#
    .SYNOPSIS
        Registers a scriptblock that receives every log line (used by the GUI).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock] $Sink
    )

    [void]$script:SigmaLogSinks.Add($Sink)
}

function Clear-SigmaLogSinks {
    $script:SigmaLogSinks.Clear()
}

function Write-SigmaLog {
    <#
    .SYNOPSIS
        Writes a log entry.
    .PARAMETER Level
        Info, Success, Warn, Error or Debug. Debug entries only reach the log
        file unless -Verbose logging was requested.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Message,

        [ValidateSet('Info', 'Success', 'Warn', 'Error', 'Debug')]
        [string] $Level = 'Info',

        [switch] $NoConsole
    )

    $stamp = Get-Date -Format 'HH:mm:ss'
    $line = '[{0}] [{1}] {2}' -f $stamp, $Level.ToUpperInvariant().PadRight(7), $Message

    if ($script:SigmaLogFile) {
        try {
            Add-Content -LiteralPath $script:SigmaLogFile -Value $line -Encoding utf8 -ErrorAction Stop
        } catch {
            # A failure to log must never take the application down.
        }
    }

    if ($Level -eq 'Debug' -and -not $script:SigmaVerbose) {
        return
    }

    if (-not $NoConsole -and -not $script:SigmaQuiet) {
        $color = switch ($Level) {
            'Success' { 'Green' }
            'Warn'    { 'Yellow' }
            'Error'   { 'Red' }
            'Debug'   { 'DarkGray' }
            default   { 'Gray' }
        }
        Write-Host $line -ForegroundColor $color
    }

    foreach ($sink in $script:SigmaLogSinks) {
        try {
            & $sink $line $Level
        } catch {
            # Ignore sink failures; the GUI may have been closed already.
        }
    }
}
