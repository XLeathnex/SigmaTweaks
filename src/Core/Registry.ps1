<#
.SYNOPSIS
    Registry helpers with creation, comparison and safe deletion semantics.
.DESCRIPTION
    Every registry operation in SigmaTweaks funnels through this file so that
    path normalisation, missing-key creation and value comparison behave
    identically for the engine, the backup writer and the state tester.
#>

function ConvertTo-SigmaRegistryPath {
    <#
    .SYNOPSIS
        Normalises 'HKLM\Foo', 'HKEY_LOCAL_MACHINE\Foo' and 'HKLM:\Foo' to a
        PowerShell provider path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $p = $Path.Trim()

    $map = @{
        'HKEY_LOCAL_MACHINE'  = 'HKLM:'
        'HKEY_CURRENT_USER'   = 'HKCU:'
        'HKEY_CLASSES_ROOT'   = 'HKCR:'
        'HKEY_USERS'          = 'HKU:'
        'HKEY_CURRENT_CONFIG' = 'HKCC:'
    }

    foreach ($long in $map.Keys) {
        if ($p -match "^$long\\") {
            $p = $map[$long] + $p.Substring($long.Length)
            break
        }
    }

    if ($p -match '^(HKLM|HKCU|HKCR|HKU|HKCC)\\') {
        $p = $p.Insert($p.IndexOf('\'), ':')
    }

    return $p
}

function Initialize-SigmaRegistryDrives {
    <#
    .SYNOPSIS
        Maps the HKCR/HKU drives that PowerShell does not provide by default.
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-PSDrive -Name 'HKCR' -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name 'HKCR' -PSProvider Registry -Root 'HKEY_CLASSES_ROOT' -Scope Global -ErrorAction SilentlyContinue | Out-Null
    }
    if (-not (Get-PSDrive -Name 'HKU' -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name 'HKU' -PSProvider Registry -Root 'HKEY_USERS' -Scope Global -ErrorAction SilentlyContinue | Out-Null
    }
}

function Get-SigmaRegistryValue {
    <#
    .SYNOPSIS
        Reads a value and reports whether it (and its key) currently exist.
    .OUTPUTS
        PSCustomObject with Path, Name, Exists, KeyExists, Value and Type.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name
    )

    $full = ConvertTo-SigmaRegistryPath -Path $Path
    $result = [ordered]@{
        Path      = $full
        Name      = $Name
        KeyExists = $false
        Exists    = $false
        Value     = $null
        Type      = $null
    }

    if (-not (Test-Path -LiteralPath $full)) {
        return [pscustomobject]$result
    }
    $result.KeyExists = $true

    # An empty $Name refers to the key's (Default) value; GetValueNames()
    # reports that entry as an empty string, so no special casing is needed.
    try {
        $key = Get-Item -LiteralPath $full -ErrorAction Stop
        if ($key.GetValueNames() -contains $Name) {
            $result.Exists = $true
            $result.Value = $key.GetValue($Name)
            $result.Type = $key.GetValueKind($Name)
        }
    } catch {
        Write-SigmaLog "Failed reading $full\$Name : $($_.Exception.Message)" -Level Debug
    }

    return [pscustomobject]$result
}

function Set-SigmaRegistryValue {
    <#
    .SYNOPSIS
        Writes a value, creating the key path when necessary.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name,

        [Parameter(Mandatory)]
        [AllowNull()]
        $Value,

        [ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord')]
        [string] $Type = 'DWord'
    )

    $full = ConvertTo-SigmaRegistryPath -Path $Path

    if (-not $PSCmdlet.ShouldProcess("$full\$Name", "Set to '$Value' ($Type)")) {
        return $true
    }

    try {
        if (-not (Test-Path -LiteralPath $full)) {
            New-Item -Path $full -Force -ErrorAction Stop | Out-Null
            Write-SigmaLog "Created key $full" -Level Debug
        }

        New-ItemProperty -LiteralPath $full -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        Write-SigmaLog "Set $full\$Name = $Value ($Type)" -Level Debug
        return $true
    } catch {
        Write-SigmaLog "Failed to set $full\$Name : $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Remove-SigmaRegistryValue {
    <#
    .SYNOPSIS
        Deletes a value if present. A missing value is treated as success.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name
    )

    $full = ConvertTo-SigmaRegistryPath -Path $Path

    if (-not (Test-Path -LiteralPath $full)) { return $true }

    if (-not $PSCmdlet.ShouldProcess("$full\$Name", 'Remove value')) {
        return $true
    }

    try {
        Remove-ItemProperty -LiteralPath $full -Name $Name -Force -ErrorAction Stop
        Write-SigmaLog "Removed $full\$Name" -Level Debug
        return $true
    } catch [System.Management.Automation.PSArgumentException] {
        # The value was already absent.
        return $true
    } catch {
        Write-SigmaLog "Failed to remove $full\$Name : $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Remove-SigmaRegistryKey {
    <#
    .SYNOPSIS
        Deletes a key and everything under it. A missing key is success.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $full = ConvertTo-SigmaRegistryPath -Path $Path
    if (-not (Test-Path -LiteralPath $full)) { return $true }

    if (-not $PSCmdlet.ShouldProcess($full, 'Remove key')) { return $true }

    try {
        Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
        Write-SigmaLog "Removed key $full" -Level Debug
        return $true
    } catch {
        Write-SigmaLog "Failed to remove key $full : $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Test-SigmaRegistryValue {
    <#
    .SYNOPSIS
        Compares the live value against an expected one.
    .DESCRIPTION
        An expected value of $null means "the value should not exist", which is
        how tweaks express a default of "key absent".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name,

        [Parameter(Mandatory)]
        [AllowNull()]
        $Expected
    )

    $current = Get-SigmaRegistryValue -Path $Path -Name $Name

    if ($null -eq $Expected) {
        return -not $current.Exists
    }

    if (-not $current.Exists) { return $false }

    # Byte arrays and multi-strings need element-wise comparison.
    if ($Expected -is [array]) {
        if ($current.Value -isnot [array]) { return $false }
        if ($current.Value.Count -ne $Expected.Count) { return $false }
        for ($i = 0; $i -lt $Expected.Count; $i++) {
            if ("$($current.Value[$i])" -ne "$($Expected[$i])") { return $false }
        }
        return $true
    }

    return ("$($current.Value)" -eq "$Expected")
}
