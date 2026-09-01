<#
.SYNOPSIS
    Store app (Appx/MSIX) inspection and removal used by the Debloat category.
#>

# Packages that are never offered for removal. Removing any of these breaks the
# shell, the Store, app installs or the Windows Security UI, and none of them
# can be reinstalled from inside a broken system.
$script:SigmaProtectedAppx = @(
    'Microsoft.DesktopAppInstaller'
    'Microsoft.HEIFImageExtension'
    'Microsoft.NET.Native'
    'Microsoft.SecHealthUI'
    'Microsoft.Services.Store.Engagement'
    'Microsoft.StorePurchaseApp'
    'Microsoft.UI.Xaml'
    'Microsoft.VCLibs'
    'Microsoft.WindowsStore'
    'Microsoft.WindowsTerminal'
    'Microsoft.WindowsAppRuntime'
    'MicrosoftWindows.Client'
    'Microsoft.AAD.BrokerPlugin'
    'Microsoft.AccountsControl'
    'Microsoft.Windows.ShellExperienceHost'
    'Microsoft.Windows.StartMenuExperienceHost'
    'Microsoft.Windows.CloudExperienceHost'
    'Microsoft.Windows.SecureAssessmentBrowser'
    'Windows.immersivecontrolpanel'
    'Microsoft.XboxGameCallableUI'
)

function Test-SigmaProtectedAppx {
    <#
    .SYNOPSIS
        True when a package name matches the never-remove list.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $PackageName
    )

    foreach ($protected in $script:SigmaProtectedAppx) {
        if ($PackageName -like "$protected*") { return $true }
    }
    return $false
}

function Get-SigmaAppxState {
    <#
    .SYNOPSIS
        Reports whether a package is installed for the current user and whether
        it is still provisioned for new users.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $PackageName
    )

    $state = [ordered]@{
        PackageName = $PackageName
        Installed   = $false
        Provisioned = $false
        FullNames   = @()
    }

    try {
        $packages = @(Get-AppxPackage -Name $PackageName -ErrorAction Stop)
        if ($packages.Count -gt 0) {
            $state.Installed = $true
            $state.FullNames = $packages | Select-Object -ExpandProperty PackageFullName
        }
    } catch {
        Write-SigmaLog "Get-AppxPackage failed for '$PackageName': $($_.Exception.Message)" -Level Debug
    }

    try {
        $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop |
            Where-Object { $_.DisplayName -like $PackageName })
        $state.Provisioned = ($provisioned.Count -gt 0)
    } catch {
        # Requires elevation; absence of the answer is not an error here.
    }

    return [pscustomobject]$state
}

function Remove-SigmaAppx {
    <#
    .SYNOPSIS
        Removes a Store app for the current user and de-provisions it so that
        it does not come back for newly created accounts.
    .PARAMETER AllUsers
        Also remove installed copies belonging to other user profiles.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $PackageName,

        [switch] $AllUsers
    )

    if (Test-SigmaProtectedAppx -PackageName $PackageName) {
        Write-SigmaLog "Refusing to remove protected package '$PackageName'." -Level Warn
        return $false
    }

    if (-not $PSCmdlet.ShouldProcess($PackageName, 'Remove Store app')) { return $true }

    # An app that is not installed is already in the state the caller wants, so
    # this starts as success and only turns false if a removal actually fails.
    $ok = $true
    $found = $false

    try {
        $packages = @(Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue)
        if ($AllUsers) {
            $packages = @(Get-AppxPackage -Name $PackageName -AllUsers -ErrorAction SilentlyContinue)
        }

        foreach ($pkg in $packages) {
            try {
                if ($AllUsers) {
                    Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                } else {
                    Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                }
                Write-SigmaLog "Removed package $($pkg.PackageFullName)." -Level Debug
                $found = $true
            } catch {
                Write-SigmaLog "Could not remove $($pkg.PackageFullName): $($_.Exception.Message)" -Level Warn
                $ok = $false
            }
        }
    } catch {
        Write-SigmaLog "Removal of '$PackageName' failed: $($_.Exception.Message)" -Level Error
        $ok = $false
    }

    try {
        Get-AppxProvisionedPackage -Online -ErrorAction Stop |
            Where-Object { $_.DisplayName -like $PackageName } |
            ForEach-Object {
                Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop | Out-Null
                Write-SigmaLog "De-provisioned $($_.DisplayName)." -Level Debug
                $found = $true
            }
    } catch {
        Write-SigmaLog "De-provisioning '$PackageName' failed: $($_.Exception.Message)" -Level Debug
    }

    if (-not $found) {
        Write-SigmaLog "'$PackageName' is not installed on this machine." -Level Debug
    }

    return $ok
}

function Install-SigmaAppx {
    <#
    .SYNOPSIS
        Re-installs a previously removed Store app through winget.
    .DESCRIPTION
        Store apps cannot be restored from a registry backup, so reverting a
        debloat entry means fetching the package again. Without winget there is
        nothing SigmaTweaks can do beyond pointing at the Store.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $PackageName,

        [string] $WingetId
    )

    if (-not $WingetId) {
        Write-SigmaLog "No winget id is known for '$PackageName'; reinstall it from the Microsoft Store." -Level Warn
        return $false
    }

    $winget = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-SigmaLog "winget is not available; reinstall '$PackageName' from the Microsoft Store." -Level Warn
        return $false
    }

    if (-not $PSCmdlet.ShouldProcess($PackageName, 'Reinstall via winget')) { return $true }

    try {
        $wingetArgs = @('install', '--id', $WingetId, '--source', 'msstore', '--accept-package-agreements', '--accept-source-agreements', '--silent')
        $proc = Start-Process -FilePath $winget.Source -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow -ErrorAction Stop
        if ($proc.ExitCode -eq 0) {
            Write-SigmaLog "Reinstalled '$PackageName'." -Level Success
            return $true
        }
        Write-SigmaLog "winget exited with code $($proc.ExitCode) while installing '$PackageName'." -Level Warn
        return $false
    } catch {
        Write-SigmaLog "Reinstall of '$PackageName' failed: $($_.Exception.Message)" -Level Error
        return $false
    }
}
