<#
.SYNOPSIS
    File Explorer, taskbar and shell behaviour.
#>

@(
    @{
        Id              = 'explorer.fileextensions'
        Name            = 'Show file extensions'
        Category        = 'Explorer'
        Description     = 'Stops Explorer hiding the extension of known file types. Worth doing on any machine: it is the difference between seeing invoice.pdf and invoice.pdf.exe.'
        Risk            = 'Low'
        Recommended     = $true
        RequiresAdmin   = $false
        RestartExplorer = $true
        Registry        = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'HideFileExt'; Type = 'DWord'; Value = 0; Default = 1 }
        )
    }

    @{
        Id              = 'explorer.hiddenfiles'
        Name            = 'Show hidden files'
        Category        = 'Explorer'
        Description     = 'Shows files and folders marked hidden. Protected operating system files stay hidden.'
        Risk            = 'Low'
        RequiresAdmin   = $false
        RestartExplorer = $true
        Registry        = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Hidden'; Type = 'DWord'; Value = 1; Default = 2 }
        )
    }

    @{
        Id              = 'explorer.launchtothispc'
        Name            = 'Open Explorer to This PC'
        Category        = 'Explorer'
        Description     = 'Makes new Explorer windows start at This PC instead of Home / Quick access.'
        Risk            = 'Low'
        Recommended     = $true
        RequiresAdmin   = $false
        RestartExplorer = $true
        Registry        = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'LaunchTo'; Type = 'DWord'; Value = 1; Default = 2 }
        )
    }

    @{
        Id              = 'explorer.quickaccessrecent'
        Name            = 'Hide recent files and frequent folders'
        Category        = 'Explorer'
        Description     = 'Stops Quick access listing recently opened files and frequently used folders, so a shared screen does not advertise what you have been working on.'
        Risk            = 'Low'
        RequiresAdmin   = $false
        RestartExplorer = $true
        Registry        = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowRecent'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowFrequent'; Type = 'DWord'; Value = 0; Default = 1 }
        )
    }

    @{
        Id              = 'explorer.compactmode'
        Name            = 'Use compact spacing in Explorer'
        Category        = 'Explorer'
        Description     = 'Restores the tighter Windows 10 row spacing in file lists, fitting noticeably more per screen.'
        Risk            = 'Low'
        RequiresAdmin   = $false
        RestartExplorer = $true
        Requires        = @{ Windows11 = $true }
        Registry        = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'UseCompactMode'; Type = 'DWord'; Value = 1; Default = 0 }
        )
    }

    @{
        Id              = 'explorer.taskbarleft'
        Name            = 'Align the taskbar to the left'
        Category        = 'Explorer'
        Description     = 'Moves Start and the pinned icons back to the left edge.'
        Risk            = 'Low'
        RequiresAdmin   = $false
        RestartExplorer = $true
        Requires        = @{ Windows11 = $true }
        Registry        = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarAl'; Type = 'DWord'; Value = 0; Default = 1 }
        )
    }

    @{
        Id              = 'explorer.widgets'
        Name            = 'Remove Widgets from the taskbar'
        Category        = 'Explorer'
        Description     = 'Hides the weather and news panel and blocks it by policy, which also stops its background feed process.'
        Risk            = 'Low'
        Recommended     = $true
        RestartExplorer = $true
        Requires        = @{ Windows11 = $true }
        Registry        = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarDa'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; Name = 'AllowNewsAndInterests'; Type = 'DWord'; Value = 0; Default = $null }
        )
    }

    @{
        Id              = 'explorer.chat'
        Name            = 'Remove Chat from the taskbar'
        Category        = 'Explorer'
        Description     = 'Hides the consumer Teams chat button. Teams itself is untouched.'
        Risk            = 'Low'
        Recommended     = $true
        RequiresAdmin   = $false
        RestartExplorer = $true
        Requires        = @{ Windows11 = $true }
        Registry        = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarMn'; Type = 'DWord'; Value = 0; Default = 1 }
        )
    }

    @{
        Id              = 'explorer.taskview'
        Name            = 'Remove the Task View button'
        Category        = 'Explorer'
        Description     = 'Hides the Task View icon. Win+Tab still works.'
        Risk            = 'Low'
        RequiresAdmin   = $false
        RestartExplorer = $true
        Registry        = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowTaskViewButton'; Type = 'DWord'; Value = 0; Default = 1 }
        )
    }

    @{
        Id              = 'explorer.searchicon'
        Name            = 'Shrink the taskbar search box to an icon'
        Category        = 'Explorer'
        Description     = 'Replaces the wide search field with a single magnifier icon, giving the taskbar back to your pinned apps.'
        Risk            = 'Low'
        RequiresAdmin   = $false
        RestartExplorer = $true
        Requires        = @{ Windows11 = $true }
        Registry        = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'SearchboxTaskbarMode'; Type = 'DWord'; Value = 1; Default = 2 }
        )
    }

    @{
        Id              = 'explorer.endtask'
        Name            = 'Add End Task to the taskbar right-click menu'
        Category        = 'Explorer'
        Description     = 'Lets you kill a hung app straight from its taskbar button instead of opening Task Manager.'
        Risk            = 'Low'
        Recommended     = $true
        RequiresAdmin   = $false
        RestartExplorer = $true
        Requires        = @{ Windows11 = $true; MinBuild = 22621 }
        Registry        = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings'; Name = 'TaskbarEndTask'; Type = 'DWord'; Value = 1; Default = 0 }
        )
    }

    @{
        Id          = 'explorer.darkmode'
        Name        = 'Use the dark theme'
        Category    = 'Explorer'
        Description = 'Switches both the shell and apps to dark mode.'
        Risk        = 'Low'
        RequiresAdmin = $false
        RestartExplorer = $true
        Registry    = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'AppsUseLightTheme'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'SystemUsesLightTheme'; Type = 'DWord'; Value = 0; Default = 1 }
        )
    }

    @{
        Id          = 'explorer.shortcutsuffix'
        Name        = 'Drop the " - Shortcut" suffix'
        Category    = 'Explorer'
        Description = 'New shortcuts are named after their target instead of gaining a suffix. Existing shortcuts keep their current names.'
        Risk        = 'Low'
        Registry    = @(
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\NamingTemplates'; Name = 'ShortcutNameTemplate'; Type = 'String'; Value = '"%s.lnk"'; Default = $null }
        )
    }

    @{
        Id          = 'explorer.verbosestatus'
        Name        = 'Show detailed startup and shutdown messages'
        Category    = 'Explorer'
        Description = 'Replaces the spinner during logon and shutdown with the name of whatever is actually running. Useful when something is holding up boot.'
        Risk        = 'Low'
        Registry    = @(
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'VerboseStatus'; Type = 'DWord'; Value = 1; Default = $null }
        )
    }

    @{
        Id          = 'explorer.numlock'
        Name        = 'Turn NumLock on at sign-in'
        Category    = 'Explorer'
        Description = 'Enables NumLock on the lock screen and for new sessions, so typing a numeric PIN works straight away.'
        Risk        = 'Low'
        Apply       = {
            Initialize-SigmaRegistryDrives
            $ok = Set-SigmaRegistryValue -Path 'HKCU:\Control Panel\Keyboard' -Name 'InitialKeyboardIndicators' -Type String -Value '2'
            $ok = (Set-SigmaRegistryValue -Path 'HKU:\.DEFAULT\Control Panel\Keyboard' -Name 'InitialKeyboardIndicators' -Type String -Value '2') -and $ok
            return $ok
        }
        Revert      = {
            Initialize-SigmaRegistryDrives
            $ok = Set-SigmaRegistryValue -Path 'HKCU:\Control Panel\Keyboard' -Name 'InitialKeyboardIndicators' -Type String -Value '2147483648'
            $ok = (Set-SigmaRegistryValue -Path 'HKU:\.DEFAULT\Control Panel\Keyboard' -Name 'InitialKeyboardIndicators' -Type String -Value '2147483648') -and $ok
            return $ok
        }
        Test        = {
            $value = Get-SigmaRegistryValue -Path 'HKCU:\Control Panel\Keyboard' -Name 'InitialKeyboardIndicators'
            if (-not $value.Exists) { return 'NotApplied' }
            return $(if ("$($value.Value)" -eq '2') { 'Applied' } else { 'NotApplied' })
        }
    }

    @{
        Id              = 'explorer.classiccontextmenu'
        Name            = 'Restore the full right-click menu'
        Category        = 'Explorer'
        Description     = 'Brings back the Windows 10 context menu so you no longer have to click "Show more options" to reach the entries your other programs add.'
        Risk            = 'Low'
        Recommended     = $true
        RequiresAdmin   = $false
        RestartExplorer = $true
        Requires        = @{ Windows11 = $true }
        Apply           = {
            # An empty InprocServer32 default value tells the shell that no
            # handler implements the compact menu, so it falls back to the old one.
            $key = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
            return (Set-SigmaRegistryValue -Path $key -Name '' -Type String -Value '')
        }
        Revert          = {
            return (Remove-SigmaRegistryKey -Path 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}')
        }
        Test            = {
            $key = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
            $value = Get-SigmaRegistryValue -Path $key -Name ''
            return $(if ($value.KeyExists) { 'Applied' } else { 'NotApplied' })
        }
    }
)
