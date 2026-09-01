<#
.SYNOPSIS
    Removal of pre-installed Store apps.
.NOTES
    Removal is one-way: SigmaTweaks cannot put a Store app back, so every entry
    here is marked Irreversible and reverting one tells you to reinstall from
    the Microsoft Store. Packages the shell, the Store or Windows Security
    depend on are on the protected list in src/Core/Appx.ps1 and are never
    offered.
#>

@(
    @{
        Id           = 'debloat.bingnews'
        Name         = 'Remove Microsoft News'
        Category     = 'Debloat'
        Description  = 'Removes the Bing-powered News app that feeds the Widgets panel.'
        Risk         = 'Low'
        Recommended  = $true
        Irreversible = $true
        Appx         = @( @{ PackageName = 'Microsoft.BingNews' } )
    }

    @{
        Id           = 'debloat.bingweather'
        Name         = 'Remove MSN Weather'
        Category     = 'Debloat'
        Description  = 'Removes the Weather app.'
        Risk         = 'Low'
        Recommended  = $true
        Irreversible = $true
        Appx         = @( @{ PackageName = 'Microsoft.BingWeather' } )
    }

    @{
        Id           = 'debloat.solitaire'
        Name         = 'Remove Microsoft Solitaire Collection'
        Category     = 'Debloat'
        Description  = 'Removes the bundled card games and their ads.'
        Risk         = 'Low'
        Recommended  = $true
        Irreversible = $true
        Appx         = @( @{ PackageName = 'Microsoft.MicrosoftSolitaireCollection' } )
    }

    @{
        Id           = 'debloat.officehub'
        Name         = 'Remove the Office / Microsoft 365 stub'
        Category     = 'Debloat'
        Description  = 'Removes the "Get Office" promotional launcher. A real Office or Microsoft 365 installation is a separate desktop program and is not affected.'
        Risk         = 'Low'
        Recommended  = $true
        Irreversible = $true
        Appx         = @( @{ PackageName = 'Microsoft.MicrosoftOfficeHub' } )
    }

    @{
        Id           = 'debloat.gethelp'
        Name         = 'Remove Get Help and Tips'
        Category     = 'Debloat'
        Description  = 'Removes the support-chat app and the "Tips" tour app.'
        Risk         = 'Low'
        Recommended  = $true
        Irreversible = $true
        Appx         = @(
            @{ PackageName = 'Microsoft.GetHelp' }
            @{ PackageName = 'Microsoft.Getstarted' }
        )
    }

    @{
        Id           = 'debloat.feedbackhub'
        Name         = 'Remove Feedback Hub'
        Category     = 'Debloat'
        Description  = 'Removes the app used to send feedback to Microsoft.'
        Risk         = 'Low'
        Recommended  = $true
        Irreversible = $true
        Appx         = @( @{ PackageName = 'Microsoft.WindowsFeedbackHub' } )
    }

    @{
        Id           = 'debloat.maps'
        Name         = 'Remove Maps'
        Category     = 'Debloat'
        Description  = 'Removes the Windows Maps app.'
        Risk         = 'Low'
        Irreversible = $true
        Appx         = @( @{ PackageName = 'Microsoft.WindowsMaps' } )
    }

    @{
        Id           = 'debloat.people'
        Name         = 'Remove People'
        Category     = 'Debloat'
        Description  = 'Removes the People contacts app. Mail and Calendar keep their own contact handling.'
        Risk         = 'Low'
        Irreversible = $true
        Appx         = @( @{ PackageName = 'Microsoft.People' } )
    }

    @{
        Id           = 'debloat.clipchamp'
        Name         = 'Remove Clipchamp'
        Category     = 'Debloat'
        Description  = 'Removes the bundled video editor.'
        Risk         = 'Low'
        Recommended  = $true
        Irreversible = $true
        Appx         = @( @{ PackageName = 'Clipchamp.Clipchamp' } )
    }

    @{
        Id           = 'debloat.teams'
        Name         = 'Remove consumer Teams / Chat'
        Category     = 'Debloat'
        Description  = 'Removes the personal Teams app wired to the taskbar Chat button. Teams for work, installed separately, is not affected.'
        Risk         = 'Low'
        Recommended  = $true
        Irreversible = $true
        Appx         = @(
            @{ PackageName = 'MicrosoftTeams' }
            @{ PackageName = 'MSTeams' }
        )
    }

    @{
        Id           = 'debloat.yourphone'
        Name         = 'Remove Phone Link'
        Category     = 'Debloat'
        Description  = 'Removes the app that mirrors an Android or iPhone onto the desktop.'
        Risk         = 'Low'
        Irreversible = $true
        Appx         = @( @{ PackageName = 'Microsoft.YourPhone' } )
    }

    @{
        Id           = 'debloat.zunemedia'
        Name         = 'Remove Media Player and Movies & TV'
        Category     = 'Debloat'
        Description  = 'Removes the built-in media apps. Only do this if you have another player installed - nothing else on a clean install opens video files.'
        Risk         = 'Medium'
        Irreversible = $true
        Appx         = @(
            @{ PackageName = 'Microsoft.ZuneMusic' }
            @{ PackageName = 'Microsoft.ZuneVideo' }
        )
    }

    @{
        Id           = 'debloat.xboxapps'
        Name         = 'Remove the Xbox apps and overlay'
        Category     = 'Debloat'
        Description  = 'Removes the Xbox console companion, the Game Bar overlay and its speech overlay. The Xbox identity provider is kept, so games that sign in with a Microsoft account still work.'
        Risk         = 'Medium'
        Irreversible = $true
        Appx         = @(
            @{ PackageName = 'Microsoft.XboxApp' }
            @{ PackageName = 'Microsoft.Xbox.TCUI' }
            @{ PackageName = 'Microsoft.XboxGameOverlay' }
            @{ PackageName = 'Microsoft.XboxGamingOverlay' }
            @{ PackageName = 'Microsoft.XboxSpeechToTextOverlay' }
        )
    }

    @{
        Id           = 'debloat.mixedreality'
        Name         = 'Remove Mixed Reality Portal and 3D Viewer'
        Category     = 'Debloat'
        Description  = 'Removes two leftovers from the Windows Mixed Reality era.'
        Risk         = 'Low'
        Recommended  = $true
        Irreversible = $true
        Appx         = @(
            @{ PackageName = 'Microsoft.MixedReality.Portal' }
            @{ PackageName = 'Microsoft.Microsoft3DViewer' }
        )
    }

    @{
        Id           = 'debloat.skype'
        Name         = 'Remove Skype'
        Category     = 'Debloat'
        Description  = 'Removes the pre-installed Skype client.'
        Risk         = 'Low'
        Recommended  = $true
        Irreversible = $true
        Appx         = @( @{ PackageName = 'Microsoft.SkypeApp' } )
    }

    @{
        Id           = 'debloat.powerautomate'
        Name         = 'Remove Power Automate Desktop'
        Category     = 'Debloat'
        Description  = 'Removes the bundled desktop automation designer.'
        Risk         = 'Low'
        Recommended  = $true
        Irreversible = $true
        Appx         = @( @{ PackageName = 'Microsoft.PowerAutomateDesktop' } )
    }

    @{
        Id           = 'debloat.todos'
        Name         = 'Remove Microsoft To Do'
        Category     = 'Debloat'
        Description  = 'Removes the To Do task app.'
        Risk         = 'Low'
        Irreversible = $true
        Appx         = @( @{ PackageName = 'Microsoft.Todos' } )
    }

    @{
        Id           = 'debloat.quickassist'
        Name         = 'Remove Quick Assist'
        Category     = 'Debloat'
        Description  = 'Removes the remote-help tool. Worth removing on a machine whose user might be talked into starting it by a phone scammer.'
        Risk         = 'Low'
        Irreversible = $true
        Appx         = @( @{ PackageName = 'MicrosoftCorporationII.QuickAssist' } )
    }

    @{
        Id           = 'debloat.copilotapp'
        Name         = 'Remove the Copilot app'
        Category     = 'Debloat'
        Description  = 'Removes the Copilot Store app. Pair this with the Copilot policy tweak under Privacy to keep it from coming back through the shell.'
        Risk         = 'Low'
        Irreversible = $true
        Requires     = @{ Windows11 = $true }
        Appx         = @(
            @{ PackageName = 'Microsoft.Copilot' }
            @{ PackageName = 'Microsoft.Windows.Ai.Copilot.Provider' }
        )
    }
)
