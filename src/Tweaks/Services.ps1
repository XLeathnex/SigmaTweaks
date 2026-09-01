<#
.SYNOPSIS
    Startup type changes for services that are safe to switch off.
.NOTES
    Anything load-bearing - Defender, the firewall, Windows Update, the event
    log, networking, user profiles - is on the protected list in
    src/Core/Services.ps1 and cannot be reconfigured from here at all.
#>

@(
    @{
        Id          = 'svc.remoteregistry'
        Name        = 'Disable Remote Registry'
        Category    = 'Services'
        Description = 'Stops other machines editing this one''s registry over the network. Almost nothing on a home or workstation setup needs it.'
        Risk        = 'Low'
        Recommended = $true
        Services    = @(
            @{ Name = 'RemoteRegistry'; StartupType = 'Disabled'; Default = 'Manual'; Stop = $true }
        )
    }

    @{
        Id          = 'svc.remoteassistance'
        Name        = 'Disable Remote Assistance'
        Category    = 'Services'
        Description = 'Refuses inbound Remote Assistance invitations. Quick Assist and Remote Desktop are separate features and keep working.'
        Risk        = 'Low'
        Recommended = $true
        Registry    = @(
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance'; Name = 'fAllowToGetHelp'; Type = 'DWord'; Value = 0; Default = 1 }
        )
    }

    @{
        Id          = 'svc.fax'
        Name        = 'Disable the Fax service'
        Category    = 'Services'
        Description = 'Turns off fax send and receive.'
        Risk        = 'Low'
        Recommended = $true
        Services    = @(
            @{ Name = 'Fax'; StartupType = 'Disabled'; Default = 'Manual'; Stop = $true }
        )
    }

    @{
        Id          = 'svc.retaildemo'
        Name        = 'Disable Retail Demo'
        Category    = 'Services'
        Description = 'The in-store demo mode service. It has no purpose outside a shop display.'
        Risk        = 'Low'
        Recommended = $true
        Services    = @(
            @{ Name = 'RetailDemo'; StartupType = 'Disabled'; Default = 'Manual'; Stop = $true }
        )
    }

    @{
        Id          = 'svc.wmpnetwork'
        Name        = 'Disable Windows Media Player network sharing'
        Category    = 'Services'
        Description = 'Stops the service that streams your media library to other devices on the network.'
        Risk        = 'Low'
        Recommended = $true
        Services    = @(
            @{ Name = 'WMPNetworkSvc'; StartupType = 'Disabled'; Default = 'Manual'; Stop = $true }
        )
    }

    @{
        Id          = 'svc.mapsbroker'
        Name        = 'Disable the offline maps downloader'
        Category    = 'Services'
        Description = 'Stops background downloads of offline map data. The Maps app still works online.'
        Risk        = 'Low'
        Services    = @(
            @{ Name = 'MapsBroker'; StartupType = 'Disabled'; Default = 'Automatic'; Stop = $true }
        )
    }

    @{
        Id          = 'svc.spooler'
        Name        = 'Disable the Print Spooler'
        Category    = 'Services'
        Description = 'Printing stops working entirely, including "print to PDF". Pick this only on a machine with no printer; the spooler has a long history of privilege-escalation bugs, so switching it off on a printer-less box is worth doing.'
        Risk        = 'Medium'
        Services    = @(
            @{ Name = 'Spooler'; StartupType = 'Disabled'; Default = 'Automatic'; Stop = $true }
        )
    }

    @{
        Id          = 'svc.wsearch'
        Name        = 'Disable Windows Search indexing'
        Category    = 'Services'
        Description = 'Stops the indexer, which removes a steady background disk and CPU load. In exchange, Start menu and Explorer searches fall back to slow live scans, and Outlook search degrades badly. Worth it on a weak machine, painful on a busy one.'
        Risk        = 'High'
        Services    = @(
            @{ Name = 'WSearch'; StartupType = 'Disabled'; Default = 'Automatic'; Stop = $true }
        )
    }

    @{
        Id          = 'svc.deliveryoptimization'
        Name        = 'Stop Delivery Optimization from starting itself'
        Category    = 'Services'
        Description = 'Sets the peer-to-peer update cache service to manual start so it stops idling in the background. Windows Update starts it on demand when it genuinely needs it.'
        Risk        = 'Low'
        Recommended = $true
        Services    = @(
            @{ Name = 'DoSvc'; StartupType = 'Manual'; Default = 'Automatic'; Stop = $true }
        )
    }

    @{
        Id          = 'svc.touchkeyboard'
        Name        = 'Disable the touch keyboard service'
        Category    = 'Services'
        Description = 'Turns off the on-screen keyboard and handwriting panel service. This also disables the emoji picker (Win+.), so skip it if you use that.'
        Risk        = 'Medium'
        Services    = @(
            @{ Name = 'TabletInputService'; StartupType = 'Disabled'; Default = 'Manual'; Stop = $true }
        )
    }

    @{
        Id          = 'svc.parentalcontrols'
        Name        = 'Disable Family Safety'
        Category    = 'Services'
        Description = 'Turns off the parental-controls enforcement service. Do not use this on a machine where a child account has screen-time or content limits.'
        Risk        = 'Medium'
        Services    = @(
            @{ Name = 'WpcMonSvc'; StartupType = 'Disabled'; Default = 'Manual'; Stop = $true }
        )
    }
)
