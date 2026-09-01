<#
.SYNOPSIS
    Latency, scheduling and capture tweaks aimed at games.
.NOTES
    Registry DWORDs whose stock value is 0xFFFFFFFF are written as -1: the
    registry stores an unsigned 32-bit word, and -1 is how .NET expresses that
    same bit pattern through an Int32.
#>

@(
    @{
        Id            = 'gaming.gamemode'
        Name          = 'Enable Game Mode'
        Category      = 'Gaming'
        Description   = 'Lets Windows prioritise the foreground game and hold back background work such as Windows Update and driver installs while you play.'
        Risk          = 'Low'
        Recommended   = $true
        RequiresAdmin = $false
        Registry      = @(
            @{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'AllowAutoGameMode'; Type = 'DWord'; Value = 1; Default = 0 }
            @{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'AutoGameModeEnabled'; Type = 'DWord'; Value = 1; Default = 0 }
        )
    }

    @{
        Id          = 'gaming.gamedvr'
        Name        = 'Disable Game DVR background recording'
        Category    = 'Gaming'
        Description = 'Game DVR keeps a rolling capture buffer running behind every game, which costs frames on mid-range GPUs. Manual recording and screenshots through Game Bar stop working.'
        Risk        = 'Low'
        Recommended = $true
        Registry    = @(
            @{ Path = 'HKCU:\System\GameConfigStore'; Name = 'GameDVR_Enabled'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; Name = 'AppCaptureEnabled'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'; Name = 'AllowGameDVR'; Type = 'DWord'; Value = 0; Default = $null }
        )
    }

    @{
        Id            = 'gaming.gamebarpopup'
        Name          = 'Stop the Game Bar popup'
        Category      = 'Gaming'
        Description   = 'Stops the "Do you want to open Game Bar?" panel appearing when a controller button is pressed or a game launches.'
        Risk          = 'Low'
        Recommended   = $true
        RequiresAdmin = $false
        Registry      = @(
            @{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'ShowStartupPanel'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'UseNexusForGameBarEnabled'; Type = 'DWord'; Value = 0; Default = 1 }
        )
    }

    @{
        Id            = 'gaming.fullscreenoptimizations'
        Name          = 'Disable fullscreen optimizations'
        Category      = 'Gaming'
        Description   = 'Forces true exclusive fullscreen instead of the borderless-window path Windows substitutes by default. Usually lowers input latency; a few games alt-tab more slowly afterwards.'
        Risk          = 'Medium'
        RequiresAdmin = $false
        Registry      = @(
            @{ Path = 'HKCU:\System\GameConfigStore'; Name = 'GameDVR_FSEBehaviorMode'; Type = 'DWord'; Value = 2; Default = 0 }
            @{ Path = 'HKCU:\System\GameConfigStore'; Name = 'GameDVR_HonorUserFSEBehaviorMode'; Type = 'DWord'; Value = 1; Default = 0 }
            @{ Path = 'HKCU:\System\GameConfigStore'; Name = 'GameDVR_DXGIHonorFSEWindowsCompatible'; Type = 'DWord'; Value = 1; Default = 0 }
            @{ Path = 'HKCU:\System\GameConfigStore'; Name = 'GameDVR_EFSEFeatureFlags'; Type = 'DWord'; Value = 0; Default = 0 }
        )
    }

    @{
        Id              = 'gaming.hags'
        Name            = 'Enable hardware-accelerated GPU scheduling'
        Category        = 'Gaming'
        Description     = 'Hands VRAM scheduling to the GPU instead of the CPU, shaving a little latency on supported cards. Needs a driver that supports it; the setting is ignored otherwise.'
        Risk            = 'Medium'
        RequiresRestart = $true
        Requires        = @{ MinBuild = 19041 }
        Registry        = @(
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name = 'HwSchMode'; Type = 'DWord'; Value = 2; Default = 1 }
        )
    }

    @{
        Id              = 'gaming.mmcss'
        Name            = 'Tune multimedia scheduling for games'
        Category        = 'Gaming'
        Description     = 'Lowers the share of CPU time MMCSS reserves for background tasks from 20% to 10%, lifts the network throttle that caps packet rates during multimedia playback, and raises the priority of the Games scheduling profile.'
        Risk            = 'Medium'
        RequiresRestart = $true
        Registry        = @(
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'SystemResponsiveness'; Type = 'DWord'; Value = 10; Default = 20 }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'NetworkThrottlingIndex'; Type = 'DWord'; Value = -1; Default = 10 }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'GPU Priority'; Type = 'DWord'; Value = 8; Default = 8 }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Priority'; Type = 'DWord'; Value = 6; Default = 2 }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Scheduling Category'; Type = 'String'; Value = 'High'; Default = 'Medium' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'SFIO Priority'; Type = 'String'; Value = 'High'; Default = 'Normal' }
        )
    }

    @{
        Id            = 'gaming.mouseaccel'
        Name          = 'Disable mouse acceleration'
        Category      = 'Gaming'
        Description   = 'Turns off "Enhance pointer precision" so cursor distance depends only on how far the mouse moved, not how fast. Makes aim consistent between sessions.'
        Risk          = 'Low'
        Recommended   = $true
        RequiresAdmin = $false
        Registry      = @(
            @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseSpeed'; Type = 'String'; Value = '0'; Default = '1' }
            @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseThreshold1'; Type = 'String'; Value = '0'; Default = '6' }
            @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseThreshold2'; Type = 'String'; Value = '0'; Default = '10' }
        )
    }

    @{
        Id              = 'gaming.xboxservices'
        Name            = 'Disable Xbox Live services'
        Category        = 'Gaming'
        Description     = 'Blocks the Xbox Live auth, save-sync and networking services from starting at all. Only pick this if you never use Game Pass, the Xbox app or an Xbox controller over Bluetooth - those all need these services and cannot start them on demand once disabled.'
        Risk            = 'Medium'
        Services        = @(
            @{ Name = 'XblAuthManager'; StartupType = 'Disabled'; Default = 'Manual'; Stop = $true }
            @{ Name = 'XblGameSave'; StartupType = 'Disabled'; Default = 'Manual'; Stop = $true }
            @{ Name = 'XboxNetApiSvc'; StartupType = 'Disabled'; Default = 'Manual'; Stop = $true }
            @{ Name = 'XboxGipSvc'; StartupType = 'Disabled'; Default = 'Manual'; Stop = $true }
        )
    }
)
