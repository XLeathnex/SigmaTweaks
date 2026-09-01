<#
.SYNOPSIS
    Windows Update behaviour.
.NOTES
    SigmaTweaks will not switch Windows Update off. Security updates are the
    single most valuable thing the OS does for you. Everything here changes
    when and how updates arrive, not whether they do.
#>

@(
    @{
        Id          = 'update.noautoreboot'
        Name        = 'Never restart automatically while signed in'
        Category    = 'Updates'
        Description = 'Windows will still install updates, but it will wait for you to restart instead of rebooting out from under an open session.'
        Risk        = 'Low'
        Recommended = $true
        Registry    = @(
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Name = 'NoAutoRebootWithLoggedOnUsers'; Type = 'DWord'; Value = 1; Default = $null }
        )
    }

    @{
        Id          = 'update.nodrivers'
        Name        = 'Do not deliver drivers through Windows Update'
        Category    = 'Updates'
        Description = 'Keeps Windows Update from replacing your GPU, audio or chipset drivers with its own generic versions. Install drivers from the vendor instead.'
        Risk        = 'Low'
        Recommended = $true
        Registry    = @(
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name = 'ExcludeWUDriversInQualityUpdate'; Type = 'DWord'; Value = 1; Default = $null }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching'; Name = 'SearchOrderConfig'; Type = 'DWord'; Value = 0; Default = 1 }
        )
    }

    @{
        Id          = 'update.deliveryoptimization'
        Name        = 'Stop sharing updates with other PCs'
        Category    = 'Updates'
        Description = 'Sets Delivery Optimization to download from Microsoft only, instead of also uploading update chunks to other machines on the internet.'
        Risk        = 'Low'
        Recommended = $true
        Registry    = @(
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; Name = 'DODownloadMode'; Type = 'DWord'; Value = 0; Default = $null }
        )
    }

    @{
        Id          = 'update.noautoappupdate'
        Name        = 'Stop the Store updating apps automatically'
        Category    = 'Updates'
        Description = 'Store apps update only when you ask. Handy on a metered connection; remember to update by hand now and then.'
        Risk        = 'Medium'
        Registry    = @(
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore'; Name = 'AutoDownload'; Type = 'DWord'; Value = 2; Default = $null }
        )
    }

    @{
        Id          = 'update.notifybeforedownload'
        Name        = 'Ask before downloading updates'
        Category    = 'Updates'
        Description = 'Windows notifies you that updates are available and waits for you to start the download. Updates you never approve are never installed, so only choose this if you will actually check.'
        Risk        = 'High'
        Registry    = @(
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Name = 'NoAutoUpdate'; Type = 'DWord'; Value = 0; Default = $null }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Name = 'AUOptions'; Type = 'DWord'; Value = 2; Default = $null }
        )
    }
)
