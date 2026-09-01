<#
.SYNOPSIS
    Power plan and sleep behaviour.
#>

@(
    @{
        Id          = 'power.ultimateperformance'
        Name        = 'Enable the Ultimate Performance power plan'
        Category    = 'Power'
        Description = 'Unhides the hidden Ultimate Performance scheme and makes it active. It removes the micro-latencies that come from parking cores and ramping clocks. On a laptop this will noticeably shorten battery life.'
        Risk        = 'Medium'
        Apply       = {
            # The GUID below is the well-known template Windows ships hidden.
            $template = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
            $duplicate = & powercfg.exe -duplicatescheme $template 2>&1

            $scheme = $null
            if ($duplicate -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                $scheme = $Matches[1]
            } else {
                # Already duplicated on an earlier run: find it in the list.
                $listed = & powercfg.exe /list 2>&1 | Where-Object { $_ -match 'Ultimate Performance' } | Select-Object -First 1
                if ($listed -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                    $scheme = $Matches[1]
                }
            }

            if (-not $scheme) {
                Write-SigmaLog 'The Ultimate Performance plan is not available on this system.' -Level Warn
                return $false
            }

            & powercfg.exe /setactive $scheme | Out-Null
            Write-SigmaLog "Activated power scheme $scheme." -Level Debug
            return $true
        }
        Revert      = {
            # 381b4222 is the stock Balanced scheme.
            & powercfg.exe /setactive '381b4222-f694-41f0-9685-ff5bb260df2e' | Out-Null
            return $true
        }
        Test        = {
            $active = & powercfg.exe /getactivescheme 2>&1
            return $(if ($active -match 'Ultimate Performance') { 'Applied' } else { 'NotApplied' })
        }
    }

    @{
        Id          = 'power.usbselectivesuspend'
        Name        = 'Disable USB selective suspend'
        Category    = 'Power'
        Description = 'Stops Windows powering down idle USB ports. Fixes mice, controllers and audio interfaces that drop out after a few seconds of inactivity, at a small cost in idle power draw.'
        Risk        = 'Low'
        Apply       = {
            # 2a737441 = USB settings subgroup, 48e6b7a6 = selective suspend.
            & powercfg.exe /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 | Out-Null
            & powercfg.exe /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 | Out-Null
            & powercfg.exe /setactive SCHEME_CURRENT | Out-Null
            return $true
        }
        Revert      = {
            & powercfg.exe /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1 | Out-Null
            & powercfg.exe /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1 | Out-Null
            & powercfg.exe /setactive SCHEME_CURRENT | Out-Null
            return $true
        }
        Test        = {
            $output = & powercfg.exe /query SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 2>&1
            $acLine = $output | Where-Object { $_ -match 'Current AC Power Setting Index' } | Select-Object -First 1
            if (-not $acLine) { return 'Unknown' }
            return $(if ($acLine -match '0x0{8}') { 'Applied' } else { 'NotApplied' })
        }
    }

    @{
        Id          = 'power.neversleepac'
        Name        = 'Never sleep while plugged in'
        Category    = 'Power'
        Description = 'Sets the sleep and hibernate timers to Never on AC power. The display still turns off on its own schedule.'
        Risk        = 'Low'
        Apply       = {
            & powercfg.exe /change standby-timeout-ac 0 | Out-Null
            & powercfg.exe /change hibernate-timeout-ac 0 | Out-Null
            return $true
        }
        Revert      = {
            & powercfg.exe /change standby-timeout-ac 30 | Out-Null
            & powercfg.exe /change hibernate-timeout-ac 180 | Out-Null
            return $true
        }
        Test        = {
            # 29f6c1db is the sleep subgroup, 29f6c1db... /238c9fa8 is sleep-after.
            $output = & powercfg.exe /query SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 2>&1
            $acLine = $output | Where-Object { $_ -match 'Current AC Power Setting Index' } | Select-Object -First 1
            if (-not $acLine) { return 'Unknown' }
            return $(if ($acLine -match '0x0{8}') { 'Applied' } else { 'NotApplied' })
        }
    }

    @{
        Id          = 'power.hiddenplans'
        Name        = 'Unhide all power plans in Control Panel'
        Category    = 'Power'
        Description = 'Makes High Performance and the other schemes Windows hides on modern standby laptops selectable again.'
        Risk        = 'Low'
        Registry    = @(
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'CsEnabled'; Type = 'DWord'; Value = 0; Default = 1 }
        )
        RequiresRestart = $true
    }
)
