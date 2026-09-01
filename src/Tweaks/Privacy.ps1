<#
.SYNOPSIS
    Telemetry, tracking and advertising tweaks.
.NOTES
    Nothing in this file touches Microsoft Defender, SmartScreen, UAC or the
    firewall. Turning security features off is not privacy, and SigmaTweaks
    does not offer it.
#>

@(
    @{
        Id             = 'privacy.telemetry'
        Name           = 'Disable diagnostic data collection'
        Category       = 'Privacy'
        Description    = 'Sets the diagnostic data policy to the lowest level, stops the Connected User Experiences and Telemetry service, and disables the Compatibility Appraiser and CEIP tasks that feed it. Home and Pro still send basic required data; only Enterprise and Education honour a full zero.'
        Risk           = 'Low'
        Recommended    = $true
        Registry       = @(
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Type = 'DWord'; Value = 0; Default = $null }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'; Name = 'AllowTelemetry'; Type = 'DWord'; Value = 0; Default = $null }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'DoNotShowFeedbackNotifications'; Type = 'DWord'; Value = 1; Default = $null }
        )
        Services       = @(
            @{ Name = 'DiagTrack'; StartupType = 'Disabled'; Default = 'Automatic'; Stop = $true }
            @{ Name = 'dmwappushservice'; StartupType = 'Disabled'; Default = 'Manual'; Stop = $true }
        )
        ScheduledTasks = @(
            @{ TaskPath = '\Microsoft\Windows\Application Experience\'; TaskName = 'Microsoft Compatibility Appraiser' }
            @{ TaskPath = '\Microsoft\Windows\Application Experience\'; TaskName = 'ProgramDataUpdater' }
            @{ TaskPath = '\Microsoft\Windows\Application Experience\'; TaskName = 'PcaPatchDbTask' }
            @{ TaskPath = '\Microsoft\Windows\Customer Experience Improvement Program\'; TaskName = 'Consolidator' }
            @{ TaskPath = '\Microsoft\Windows\Customer Experience Improvement Program\'; TaskName = 'UsbCeip' }
            @{ TaskPath = '\Microsoft\Windows\Autochk\'; TaskName = 'Proxy' }
        )
    }

    @{
        Id            = 'privacy.advertisingid'
        Name          = 'Disable the advertising ID'
        Category      = 'Privacy'
        Description   = 'Stops apps from reading the per-user advertising identifier used to correlate you across Store apps. Ads still appear; they stop being personalised.'
        Risk          = 'Low'
        Recommended   = $true
        Registry      = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo'; Name = 'DisabledByGroupPolicy'; Type = 'DWord'; Value = 1; Default = $null }
        )
    }

    @{
        Id            = 'privacy.tailored'
        Name          = 'Disable tailored experiences'
        Category      = 'Privacy'
        Description   = 'Stops Windows from using your diagnostic data to personalise tips, ads and recommendations in the shell.'
        Risk          = 'Low'
        Recommended   = $true
        RequiresAdmin = $false
        Registry      = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'; Name = 'TailoredExperiencesWithDiagnosticDataEnabled'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableTailoredExperiencesWithDiagnosticData'; Type = 'DWord'; Value = 1; Default = $null }
        )
    }

    @{
        Id            = 'privacy.suggestions'
        Name          = 'Remove suggestions, tips and Start menu ads'
        Category      = 'Privacy'
        Description   = 'Clears the Content Delivery Manager flags behind "suggested" Start menu entries, lock screen adverts, silently installed promo apps and the "Get even more out of Windows" nag.'
        Risk          = 'Low'
        Recommended   = $true
        RequiresAdmin = $false
        Registry      = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SystemPaneSuggestionsEnabled'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SilentInstalledAppsEnabled'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'PreInstalledAppsEnabled'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'OemPreInstalledAppsEnabled'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SoftLandingEnabled'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'RotatingLockScreenOverlayEnabled'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338388Enabled'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338389Enabled'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338393Enabled'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353694Enabled'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353696Enabled'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement'; Name = 'ScoobeSystemSettingEnabled'; Type = 'DWord'; Value = 0; Default = 1 }
        )
    }

    @{
        Id          = 'privacy.activityhistory'
        Name        = 'Disable activity history'
        Category    = 'Privacy'
        Description = 'Stops Windows recording which apps and documents you opened, and stops uploading that timeline to your Microsoft account.'
        Risk        = 'Low'
        Recommended = $true
        Registry    = @(
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'EnableActivityFeed'; Type = 'DWord'; Value = 0; Default = $null }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'PublishUserActivities'; Type = 'DWord'; Value = 0; Default = $null }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'UploadUserActivities'; Type = 'DWord'; Value = 0; Default = $null }
        )
    }

    @{
        Id            = 'privacy.apptracking'
        Name          = 'Stop tracking app launches'
        Category      = 'Privacy'
        Description   = 'Windows counts how often you start each program to order the "Most used" list. This turns that counting off.'
        Risk          = 'Low'
        RequiresAdmin = $false
        Registry      = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackProgs'; Type = 'DWord'; Value = 0; Default = 1 }
        )
    }

    @{
        Id          = 'privacy.cortana'
        Name        = 'Disable Cortana'
        Category    = 'Privacy'
        Description = 'Blocks Cortana through policy. Local file and settings search keep working.'
        Risk        = 'Low'
        Recommended = $true
        Registry    = @(
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'AllowCortana'; Type = 'DWord'; Value = 0; Default = $null }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'AllowCloudSearch'; Type = 'DWord'; Value = 0; Default = $null }
        )
    }

    @{
        Id              = 'privacy.websearch'
        Name            = 'Remove web results from Start menu search'
        Category        = 'Privacy'
        Description     = 'Search stops querying Bing and stops sending your typed query to Microsoft. Only local results are returned, which also makes search noticeably faster.'
        Risk            = 'Low'
        Recommended     = $true
        RestartExplorer = $true
        Registry        = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'BingSearchEnabled'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'CortanaConsent'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'; Name = 'DisableSearchBoxSuggestions'; Type = 'DWord'; Value = 1; Default = $null }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'DisableWebSearch'; Type = 'DWord'; Value = 1; Default = $null }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'ConnectedSearchUseWeb'; Type = 'DWord'; Value = 0; Default = $null }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'IsDynamicSearchBoxEnabled'; Type = 'DWord'; Value = 0; Default = 1 }
        )
    }

    @{
        Id          = 'privacy.copilot'
        Name        = 'Disable Windows Copilot'
        Category    = 'Privacy'
        Description = 'Turns off the Copilot side panel and removes its taskbar entry through policy.'
        Risk        = 'Low'
        Requires    = @{ Windows11 = $true }
        Registry    = @(
            @{ Path = 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Type = 'DWord'; Value = 1; Default = $null }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Type = 'DWord'; Value = 1; Default = $null }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowCopilotButton'; Type = 'DWord'; Value = 0; Default = 1 }
        )
    }

    @{
        Id          = 'privacy.recall'
        Name        = 'Disable Recall snapshots'
        Category    = 'Privacy'
        Description = 'Blocks the Windows AI feature that periodically screenshots everything you do and indexes it locally. Only present on Copilot+ hardware, but the policy is harmless elsewhere.'
        Risk        = 'Low'
        Recommended = $true
        Requires    = @{ Windows11 = $true; MinBuild = 22000 }
        Registry    = @(
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAIDataAnalysis'; Type = 'DWord'; Value = 1; Default = $null }
            @{ Path = 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAIDataAnalysis'; Type = 'DWord'; Value = 1; Default = $null }
        )
    }

    @{
        Id            = 'privacy.feedback'
        Name          = 'Stop feedback requests'
        Category      = 'Privacy'
        Description   = 'Stops Windows asking how likely you are to recommend it, and disables the feedback upload tasks.'
        Risk          = 'Low'
        Recommended   = $true
        RequiresAdmin = $false
        Registry      = @(
            @{ Path = 'HKCU:\Software\Microsoft\Siuf\Rules'; Name = 'NumberOfSIUFInPeriod'; Type = 'DWord'; Value = 0; Default = $null }
            @{ Path = 'HKCU:\Software\Microsoft\Siuf\Rules'; Name = 'PeriodInNanoSeconds'; Type = 'DWord'; Value = 0; Default = $null }
        )
        ScheduledTasks = @(
            @{ TaskPath = '\Microsoft\Windows\Feedback\Siuf\'; TaskName = 'DmClient' }
            @{ TaskPath = '\Microsoft\Windows\Feedback\Siuf\'; TaskName = 'DmClientOnScenarioDownload' }
        )
    }

    @{
        Id          = 'privacy.speech'
        Name        = 'Disable online speech recognition'
        Category    = 'Privacy'
        Description = 'Stops voice input being sent to Microsoft for processing. Offline speech recognition still works.'
        Risk        = 'Low'
        Registry    = @(
            @{ Path = 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'; Name = 'HasAccepted'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization'; Name = 'AllowInputPersonalization'; Type = 'DWord'; Value = 0; Default = $null }
        )
    }

    @{
        Id            = 'privacy.inking'
        Name          = 'Disable inking and typing personalisation'
        Category      = 'Privacy'
        Description   = 'Stops Windows building a personal dictionary from what you type and write, and stops harvesting contact names for it.'
        Risk          = 'Low'
        Recommended   = $true
        RequiresAdmin = $false
        Registry      = @(
            @{ Path = 'HKCU:\Software\Microsoft\InputPersonalization'; Name = 'RestrictImplicitInkCollection'; Type = 'DWord'; Value = 1; Default = 0 }
            @{ Path = 'HKCU:\Software\Microsoft\InputPersonalization'; Name = 'RestrictImplicitTextCollection'; Type = 'DWord'; Value = 1; Default = 0 }
            @{ Path = 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore'; Name = 'HarvestContacts'; Type = 'DWord'; Value = 0; Default = 1 }
            @{ Path = 'HKCU:\Software\Microsoft\Personalization\Settings'; Name = 'AcceptedPrivacyPolicy'; Type = 'DWord'; Value = 0; Default = 1 }
        )
    }

    @{
        Id          = 'privacy.location'
        Name        = 'Deny location access'
        Category    = 'Privacy'
        Description = 'Sets the system-wide location consent to Deny and stops the geolocation service. Maps, Weather and "find my device" stop knowing where you are.'
        Risk        = 'Medium'
        Registry    = @(
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'; Name = 'Value'; Type = 'String'; Value = 'Deny'; Default = 'Allow' }
        )
        Services    = @(
            @{ Name = 'lfsvc'; StartupType = 'Disabled'; Default = 'Manual'; Stop = $true }
        )
    }

    @{
        Id          = 'privacy.errorreporting'
        Name        = 'Disable Windows Error Reporting'
        Category    = 'Privacy'
        Description = 'Stops crash dumps being uploaded to Microsoft. Local crash logs in Event Viewer are unaffected.'
        Risk        = 'Low'
        Registry    = @(
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting'; Name = 'Disabled'; Type = 'DWord'; Value = 1; Default = 0 }
        )
        Services    = @(
            @{ Name = 'WerSvc'; StartupType = 'Disabled'; Default = 'Manual'; Stop = $true }
        )
        ScheduledTasks = @(
            @{ TaskPath = '\Microsoft\Windows\Windows Error Reporting\'; TaskName = 'QueueReporting' }
        )
    }
)
