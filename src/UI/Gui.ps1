<#
.SYNOPSIS
    The SigmaTweaks WPF interface.
.DESCRIPTION
    The window chrome comes from MainWindow.xaml; the tweak cards are built in
    code so that every checkbox is a real control this script holds a reference
    to, rather than a binding whose state has to be inferred.

    Long operations run on the UI thread and pump the dispatcher between steps.
    A tweak batch is seconds of work, not minutes, and this keeps the whole
    application single-threaded and predictable.
#>

$script:Gui = $null

function Set-SigmaGuiBusy {
    <#
    .SYNOPSIS
        Shows or hides the "working" overlay.
    #>
    [CmdletBinding()]
    param(
        [bool] $Busy,
        [string] $Text = 'Working...'
    )

    if (-not $script:Gui) { return }

    $script:Gui.BusyText.Text = $Text
    $script:Gui.BusyOverlay.Visibility = $(if ($Busy) { 'Visible' } else { 'Collapsed' })
    Update-SigmaGuiFrame
}

function Update-SigmaGuiFrame {
    <#
    .SYNOPSIS
        Lets pending layout, render and input work run.
    .DESCRIPTION
        Called between steps of a long operation so the log pane and the busy
        overlay actually repaint while work is in progress.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:Gui) { return }

    $noop = [action]{}
    $script:Gui.Window.Dispatcher.Invoke($noop, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
}

function New-SigmaPill {
    <#
    .SYNOPSIS
        Builds a small rounded label used for risk and status badges.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Text,
        [Parameter(Mandatory)] [string] $Background,
        [string] $Foreground = '#0E1013'
    )

    $border = New-Object System.Windows.Controls.Border
    $border.CornerRadius = New-Object System.Windows.CornerRadius(10)
    $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Background)
    $border.Padding = New-Object System.Windows.Thickness(8, 2, 8, 2)
    $border.Margin = New-Object System.Windows.Thickness(6, 0, 0, 0)
    $border.VerticalAlignment = 'Center'

    $text = New-Object System.Windows.Controls.TextBlock
    $text.Text = $Text
    $text.FontSize = 11
    $text.FontWeight = 'SemiBold'
    $text.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Foreground)
    $border.Child = $text

    return $border
}

function Get-SigmaRiskColour {
    [CmdletBinding()]
    param([string] $Risk)

    switch ($Risk) {
        'High'   { return '#F03D5F' }
        'Medium' { return '#F5A524' }
        default  { return '#3FCF8E' }
    }
}

function New-SigmaTweakCard {
    <#
    .SYNOPSIS
        Builds one tweak row and registers its checkbox.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Tweak
    )

    $applicability = Test-SigmaTweakApplicable -Tweak $Tweak -SystemInfo $script:Gui.SystemInfo
    $state = $(if ($applicability.Applicable) { Test-SigmaTweak -Tweak $Tweak } else { 'NotApplicable' })

    $card = New-Object System.Windows.Controls.Border
    $card.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#16191F')
    $card.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2A2F3A')
    $card.BorderThickness = New-Object System.Windows.Thickness(1)
    $card.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $card.Padding = New-Object System.Windows.Thickness(14)
    $card.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)

    $grid = New-Object System.Windows.Controls.Grid
    foreach ($width in @('Auto', '*', 'Auto')) {
        $column = New-Object System.Windows.Controls.ColumnDefinition
        $column.Width = [System.Windows.GridLength]::Auto
        if ($width -eq '*') { $column.Width = New-Object System.Windows.GridLength(1, 'Star') }
        $grid.ColumnDefinitions.Add($column)
    }

    $check = New-Object System.Windows.Controls.CheckBox
    $check.VerticalAlignment = 'Top'
    $check.Margin = New-Object System.Windows.Thickness(0, 2, 12, 0)
    $check.IsEnabled = $applicability.Applicable
    $check.Tag = $Tweak.Id
    $check.Add_Checked({ Update-SigmaGuiSelection })
    $check.Add_Unchecked({ Update-SigmaGuiSelection })
    [System.Windows.Controls.Grid]::SetColumn($check, 0)
    $grid.Children.Add($check) | Out-Null
    $script:Gui.Checks[$Tweak.Id] = $check

    $body = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetColumn($body, 1)

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = $Tweak.Name
    $title.FontSize = 14
    $title.FontWeight = 'SemiBold'
    $title.TextWrapping = 'Wrap'
    $title.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#E6E9EF')
    $body.Children.Add($title) | Out-Null

    $description = New-Object System.Windows.Controls.TextBlock
    $description.Text = $Tweak.Description
    $description.FontSize = 12
    $description.TextWrapping = 'Wrap'
    $description.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
    $description.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#8A93A6')
    $body.Children.Add($description) | Out-Null

    $footnote = New-Object System.Windows.Controls.TextBlock
    $footnote.FontSize = 11
    $footnote.Margin = New-Object System.Windows.Thickness(0, 6, 0, 0)
    $footnote.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#5C6478')

    $notes = @($Tweak.Id)
    if ($Tweak.RequiresRestart) { $notes += 'needs a restart' }
    if ($Tweak.RestartExplorer) { $notes += 'restarts Explorer' }
    if ($Tweak.Irreversible) { $notes += 'cannot be undone' }
    if (-not $applicability.Applicable) { $notes += $applicability.Reason }
    $footnote.Text = ($notes -join '  -  ')
    $body.Children.Add($footnote) | Out-Null

    $grid.Children.Add($body) | Out-Null

    $badges = New-Object System.Windows.Controls.StackPanel
    $badges.Orientation = 'Horizontal'
    $badges.VerticalAlignment = 'Top'
    [System.Windows.Controls.Grid]::SetColumn($badges, 2)

    $badges.Children.Add((New-SigmaPill -Text $Tweak.Risk.ToUpperInvariant() -Background (Get-SigmaRiskColour -Risk $Tweak.Risk))) | Out-Null

    $statusPill = switch ($state) {
        'Applied'       { New-SigmaPill -Text 'APPLIED' -Background '#7C5CFF' -Foreground '#FFFFFF' }
        'Partial'       { New-SigmaPill -Text 'PARTIAL' -Background '#F5A524' }
        'NotApplicable' { New-SigmaPill -Text 'N/A' -Background '#3A3F4C' -Foreground '#8A93A6' }
        'Unknown'       { New-SigmaPill -Text 'UNKNOWN' -Background '#3A3F4C' -Foreground '#8A93A6' }
        default         { New-SigmaPill -Text 'OFF' -Background '#242935' -Foreground '#8A93A6' }
    }
    $badges.Children.Add($statusPill) | Out-Null

    $grid.Children.Add($badges) | Out-Null
    $card.Child = $grid

    return $card
}

function New-SigmaActionCard {
    <#
    .SYNOPSIS
        Builds one maintenance action row with its own Run button.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Action
    )

    $card = New-Object System.Windows.Controls.Border
    $card.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#16191F')
    $card.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2A2F3A')
    $card.BorderThickness = New-Object System.Windows.Thickness(1)
    $card.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $card.Padding = New-Object System.Windows.Thickness(14)
    $card.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)

    $grid = New-Object System.Windows.Controls.Grid
    $starColumn = New-Object System.Windows.Controls.ColumnDefinition
    $starColumn.Width = New-Object System.Windows.GridLength(1, 'Star')
    $autoColumn = New-Object System.Windows.Controls.ColumnDefinition
    $autoColumn.Width = [System.Windows.GridLength]::Auto
    $grid.ColumnDefinitions.Add($starColumn)
    $grid.ColumnDefinitions.Add($autoColumn)

    $body = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetColumn($body, 0)

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = $Action.Name
    $title.FontSize = 14
    $title.FontWeight = 'SemiBold'
    $title.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#E6E9EF')
    $body.Children.Add($title) | Out-Null

    $description = New-Object System.Windows.Controls.TextBlock
    $description.Text = $Action.Description
    $description.FontSize = 12
    $description.TextWrapping = 'Wrap'
    $description.Margin = New-Object System.Windows.Thickness(0, 4, 12, 0)
    $description.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#8A93A6')
    $body.Children.Add($description) | Out-Null

    $grid.Children.Add($body) | Out-Null

    $button = New-Object System.Windows.Controls.Button
    $button.Content = 'Run'
    $button.Style = $script:Gui.Window.FindResource('GhostButton')
    $button.VerticalAlignment = 'Center'
    $button.Tag = $Action.Id
    [System.Windows.Controls.Grid]::SetColumn($button, 1)

    $button.Add_Click({
        param($sender, $eventArgs)

        $actionId = $sender.Tag
        $action = Get-SigmaActionCatalog | Where-Object { $_.Id -eq $actionId } | Select-Object -First 1
        if (-not $action) { return }

        if ($action.Confirm) {
            $answer = [System.Windows.MessageBox]::Show(
                "$($action.Description)`n`nRun this now?",
                $action.Name,
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning)
            if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
        }

        $script:Gui.LogExpander.IsExpanded = $true
        Set-SigmaGuiBusy -Busy $true -Text $action.Name
        try {
            Invoke-SigmaAction -Id $actionId | Out-Null
        } finally {
            Set-SigmaGuiBusy -Busy $false
        }
    })

    $grid.Children.Add($button) | Out-Null
    $card.Child = $grid

    return $card
}

function New-SigmaSectionHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Title,
        [string] $Subtitle
    )

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = New-Object System.Windows.Thickness(0, 4, 0, 14)

    $heading = New-Object System.Windows.Controls.TextBlock
    $heading.Text = $Title
    $heading.FontSize = 20
    $heading.FontWeight = 'Bold'
    $heading.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#E6E9EF')
    $panel.Children.Add($heading) | Out-Null

    if ($Subtitle) {
        $sub = New-Object System.Windows.Controls.TextBlock
        $sub.Text = $Subtitle
        $sub.FontSize = 12
        $sub.TextWrapping = 'Wrap'
        $sub.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
        $sub.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#8A93A6')
        $panel.Children.Add($sub) | Out-Null
    }

    return $panel
}

function Show-SigmaGuiDashboard {
    <#
    .SYNOPSIS
        Renders the summary page: machine facts and how many tweaks are on.
    #>
    [CmdletBinding()]
    param()

    $panel = $script:Gui.ContentPanel
    $panel.Children.Clear()
    $panel.Children.Add((New-SigmaSectionHeader -Title 'Overview' -Subtitle 'Pick a category on the left, tick what you want and press Apply. Every change is backed up first and can be reverted.')) | Out-Null

    $info = $script:Gui.SystemInfo
    $rows = [ordered]@{
        'Computer'      = $info.ComputerName
        'Windows'       = '{0} {1} (build {2})' -f $info.OSName, $info.Edition, $info.Build
        'Processor'     = $info.CPU
        'Memory'        = '{0} GB' -f $info.MemoryGB
        'Graphics'      = $info.GPU
        'System drive'  = '{0} - {1} GB free' -f $info.SystemDrive, $info.FreeSpaceGB
        'PowerShell'    = $info.PowerShell
        'Elevated'      = $(if ($info.IsAdmin) { 'Yes' } else { 'No - most tweaks will be blocked' })
    }

    $box = New-Object System.Windows.Controls.Border
    $box.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#16191F')
    $box.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2A2F3A')
    $box.BorderThickness = New-Object System.Windows.Thickness(1)
    $box.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $box.Padding = New-Object System.Windows.Thickness(16)
    $box.Margin = New-Object System.Windows.Thickness(0, 0, 0, 14)

    $table = New-Object System.Windows.Controls.StackPanel
    foreach ($key in $rows.Keys) {
        $row = New-Object System.Windows.Controls.StackPanel
        $row.Orientation = 'Horizontal'
        $row.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)

        $label = New-Object System.Windows.Controls.TextBlock
        $label.Text = $key
        $label.Width = 130
        $label.FontSize = 12
        $label.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#8A93A6')
        $row.Children.Add($label) | Out-Null

        $value = New-Object System.Windows.Controls.TextBlock
        $value.Text = "$($rows[$key])"
        $value.FontSize = 12
        $value.TextWrapping = 'Wrap'
        $value.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#E6E9EF')
        $row.Children.Add($value) | Out-Null

        $table.Children.Add($row) | Out-Null
    }
    $box.Child = $table
    $panel.Children.Add($box) | Out-Null

    $counts = New-Object System.Windows.Controls.TextBlock
    $counts.FontSize = 12
    $counts.TextWrapping = 'Wrap'
    $counts.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#8A93A6')
    $counts.Text = '{0} tweaks across {1} categories, plus {2} maintenance actions. Presets are in the bar at the bottom.' -f
        $script:Gui.Tweaks.Count, (Get-SigmaCategory).Count, (Get-SigmaActionCatalog).Count
    $panel.Children.Add($counts) | Out-Null
}

function Show-SigmaGuiBackups {
    <#
    .SYNOPSIS
        Lists saved snapshots with a restore button on each.
    #>
    [CmdletBinding()]
    param()

    $panel = $script:Gui.ContentPanel
    $panel.Children.Clear()
    $panel.Children.Add((New-SigmaSectionHeader -Title 'Backups' -Subtitle 'Every apply writes a snapshot of the exact values it is about to change. Restoring one puts those values back, whatever they were.')) | Out-Null

    $backups = @(Get-SigmaBackup)
    if ($backups.Count -eq 0) {
        $empty = New-Object System.Windows.Controls.TextBlock
        $empty.Text = 'No backups yet. One is written automatically the first time you apply something.'
        $empty.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#8A93A6')
        $empty.FontSize = 12
        $panel.Children.Add($empty) | Out-Null
        return
    }

    foreach ($backup in $backups) {
        $card = New-Object System.Windows.Controls.Border
        $card.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#16191F')
        $card.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2A2F3A')
        $card.BorderThickness = New-Object System.Windows.Thickness(1)
        $card.CornerRadius = New-Object System.Windows.CornerRadius(8)
        $card.Padding = New-Object System.Windows.Thickness(14)
        $card.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)

        $grid = New-Object System.Windows.Controls.Grid
        $starColumn = New-Object System.Windows.Controls.ColumnDefinition
        $starColumn.Width = New-Object System.Windows.GridLength(1, 'Star')
        $autoColumn = New-Object System.Windows.Controls.ColumnDefinition
        $autoColumn.Width = [System.Windows.GridLength]::Auto
        $grid.ColumnDefinitions.Add($starColumn)
        $grid.ColumnDefinitions.Add($autoColumn)

        $body = New-Object System.Windows.Controls.StackPanel
        [System.Windows.Controls.Grid]::SetColumn($body, 0)

        $title = New-Object System.Windows.Controls.TextBlock
        $created = $backup.Created
        try { $created = ([datetime]$backup.Created).ToString('yyyy-MM-dd HH:mm:ss') } catch { }
        $title.Text = '{0}  ({1})' -f $created, $backup.Label
        $title.FontSize = 14
        $title.FontWeight = 'SemiBold'
        $title.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#E6E9EF')
        $body.Children.Add($title) | Out-Null

        $detail = New-Object System.Windows.Controls.TextBlock
        $detail.Text = '{0} tweaks, {1} recorded values  -  {2}' -f $backup.TweakCount, $backup.EntryCount, $backup.FileName
        $detail.FontSize = 12
        $detail.Margin = New-Object System.Windows.Thickness(0, 4, 12, 0)
        $detail.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#8A93A6')
        $body.Children.Add($detail) | Out-Null

        $grid.Children.Add($body) | Out-Null

        $button = New-Object System.Windows.Controls.Button
        $button.Content = 'Restore'
        $button.Style = $script:Gui.Window.FindResource('GhostButton')
        $button.VerticalAlignment = 'Center'
        $button.Tag = $backup.Path
        [System.Windows.Controls.Grid]::SetColumn($button, 1)

        $button.Add_Click({
            param($sender, $eventArgs)

            $path = $sender.Tag
            $answer = [System.Windows.MessageBox]::Show(
                "Put back every value recorded in this backup?`n`n$path",
                'Restore backup',
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Question)
            if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }

            $script:Gui.LogExpander.IsExpanded = $true
            Set-SigmaGuiBusy -Busy $true -Text 'Restoring backup...'
            try {
                Restore-SigmaBackup -Path $path | Out-Null
            } finally {
                Set-SigmaGuiBusy -Busy $false
            }
            Show-SigmaGuiCategory -Name 'Backups'
        })

        $grid.Children.Add($button) | Out-Null
        $card.Child = $grid
        $panel.Children.Add($card) | Out-Null
    }
}

function Show-SigmaGuiMaintenance {
    [CmdletBinding()]
    param()

    $panel = $script:Gui.ContentPanel
    $panel.Children.Clear()
    $panel.Children.Add((New-SigmaSectionHeader -Title 'Maintenance' -Subtitle 'One-shot jobs rather than settings. These have no state to revert, so read the description before running the ones that ask for confirmation.')) | Out-Null

    foreach ($action in (Get-SigmaActionCatalog)) {
        $panel.Children.Add((New-SigmaActionCard -Action $action)) | Out-Null
    }
}

function Show-SigmaGuiCategory {
    <#
    .SYNOPSIS
        Renders one page of the application.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name
    )

    $script:Gui.Category = $Name
    $script:Gui.Checks.Clear()
    $script:Gui.ContentScroller.ScrollToTop()

    switch ($Name) {
        'Overview'    { Show-SigmaGuiDashboard; Update-SigmaGuiSelection; return }
        'Maintenance' { Show-SigmaGuiMaintenance; Update-SigmaGuiSelection; return }
        'Backups'     { Show-SigmaGuiBackups; Update-SigmaGuiSelection; return }
    }

    $panel = $script:Gui.ContentPanel
    $panel.Children.Clear()

    $filter = $script:Gui.SearchBox.Text
    $tweaks = @($script:Gui.Tweaks | Where-Object { $_.Category -eq $Name })

    if ($filter) {
        $tweaks = @($tweaks | Where-Object {
            $_.Name -like "*$filter*" -or $_.Description -like "*$filter*" -or $_.Id -like "*$filter*"
        })
    }

    $subtitle = switch ($Name) {
        'Debloat'  { 'Removing a Store app cannot be undone from here. Anything you want back has to come from the Microsoft Store.' }
        'Services' { 'Services that keep Windows secure or connected are excluded from this list and cannot be changed by SigmaTweaks.' }
        'Updates'  { 'These change when and how updates arrive. SigmaTweaks will not switch Windows Update off.' }
        default    { '{0} tweaks in this category.' -f $tweaks.Count }
    }
    $panel.Children.Add((New-SigmaSectionHeader -Title $Name -Subtitle $subtitle)) | Out-Null

    if ($tweaks.Count -eq 0) {
        $empty = New-Object System.Windows.Controls.TextBlock
        $empty.Text = $(if ($filter) { "Nothing in $Name matches '$filter'." } else { "No tweaks in $Name." })
        $empty.FontSize = 12
        $empty.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#8A93A6')
        $panel.Children.Add($empty) | Out-Null
    }

    foreach ($tweak in $tweaks) {
        $panel.Children.Add((New-SigmaTweakCard -Tweak $tweak)) | Out-Null
    }

    Update-SigmaGuiSelection
}

function Get-SigmaGuiSelectedId {
    <#
    .SYNOPSIS
        Ids of every ticked checkbox on the current page.
    #>
    [CmdletBinding()]
    param()

    $selected = New-Object System.Collections.ArrayList
    foreach ($id in $script:Gui.Checks.Keys) {
        if ($script:Gui.Checks[$id].IsChecked) { [void]$selected.Add($id) }
    }
    return $selected.ToArray()
}

function Update-SigmaGuiSelection {
    [CmdletBinding()]
    param()

    if (-not $script:Gui) { return }

    $count = (Get-SigmaGuiSelectedId).Count
    $script:Gui.SelectionText.Text = $(if ($count -eq 0) { 'Nothing selected' } else { "$count selected" })
    $script:Gui.ApplyButton.IsEnabled = ($count -gt 0)
    $script:Gui.RevertButton.IsEnabled = ($count -gt 0)
}

function Invoke-SigmaGuiBatch {
    <#
    .SYNOPSIS
        Applies or reverts whatever is ticked on the current page.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Apply', 'Revert')]
        [string] $Mode
    )

    $ids = Get-SigmaGuiSelectedId
    if ($ids.Count -eq 0) { return }

    $tweaks = @(Get-SigmaTweakById -Id $ids)
    if ($tweaks.Count -eq 0) { return }

    $irreversible = @($tweaks | Where-Object { $_.Irreversible })
    $warning = if ($Mode -eq 'Apply' -and $irreversible.Count -gt 0) {
        "`n`n$($irreversible.Count) of these cannot be undone by SigmaTweaks:`n  " +
            (($irreversible | Select-Object -First 6 | ForEach-Object { $_.Name }) -join "`n  ")
    } else { '' }

    $answer = [System.Windows.MessageBox]::Show(
        "$Mode $($tweaks.Count) tweak(s)?$warning",
        "$Mode tweaks",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question)
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }

    $script:Gui.LogExpander.IsExpanded = $true
    $restorePoint = [bool]$script:Gui.RestorePointCheck.IsChecked
    Set-SigmaGuiBusy -Busy $true -Text "$Mode in progress..."

    $results = @()
    try {
        $results = @(Invoke-SigmaTweakSet -Tweaks $tweaks -Mode $Mode -CreateRestorePoint:$restorePoint)
    } catch {
        Write-SigmaLog "Batch failed: $($_.Exception.Message)" -Level Error
    } finally {
        Set-SigmaGuiBusy -Busy $false
    }

    Show-SigmaGuiCategory -Name $script:Gui.Category

    $changedIds = @($results | Where-Object { $_.Success } | Select-Object -ExpandProperty Id)
    $pending = @($tweaks | Where-Object { $_.RequiresRestart -and $changedIds -contains $_.Id })
    if ($pending.Count -eq 0) { return }

    $answer = [System.Windows.MessageBox]::Show(
        "$($pending.Count) of these only take effect after a restart.`n`nRestart now?",
        'Restart required',
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Information)
    if ($answer -eq [System.Windows.MessageBoxResult]::Yes) {
        Request-SigmaRestart -Confirm:$false
        $script:Gui.Window.Close()
    }
}

function Set-SigmaGuiPreset {
    <#
    .SYNOPSIS
        Ticks the boxes on the current page that belong to a preset.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Key
    )

    $preset = @(Get-SigmaPreset -Name $Key) | Select-Object -First 1
    if (-not $preset) { return }

    $selected = 0
    foreach ($id in $script:Gui.Checks.Keys) {
        $wanted = $preset.TweakIds -contains $id
        if ($wanted -and $script:Gui.Checks[$id].IsEnabled) {
            $script:Gui.Checks[$id].IsChecked = $true
            $selected++
        }
    }

    $total = @($preset.TweakIds).Count
    Write-SigmaLog "Preset '$($preset.Name)': $selected of its $total tweaks are on this page." -Level Info
    if ($selected -lt $total) {
        Write-SigmaLog 'Switch category to select the rest, or press Apply once per category.' -Level Info
    }
    Update-SigmaGuiSelection
}

function Show-SigmaGui {
    <#
    .SYNOPSIS
        Builds and shows the main window. Blocks until it is closed.
    #>
    [CmdletBinding()]
    param()

    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Add-Type -AssemblyName PresentationCore -ErrorAction Stop
    Add-Type -AssemblyName WindowsBase -ErrorAction Stop

    $xamlPath = Join-Path $script:SigmaRoot 'src\UI\MainWindow.xaml'
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "Interface definition not found: $xamlPath"
    }

    [xml]$xaml = Get-Content -LiteralPath $xamlPath -Raw
    $reader = New-Object System.Xml.XmlNodeReader($xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    $script:Gui = @{
        Window            = $window
        Checks            = @{}
        Category          = 'Overview'
        SystemInfo        = (Get-SigmaSystemInfo)
        Tweaks            = (Get-SigmaTweakCatalog)
        ContentPanel      = $window.FindName('ContentPanel')
        ContentScroller   = $window.FindName('ContentScroller')
        CategoryList      = $window.FindName('CategoryList')
        SearchBox         = $window.FindName('SearchBox')
        SelectionText     = $window.FindName('SelectionText')
        ApplyButton       = $window.FindName('ApplyButton')
        RevertButton      = $window.FindName('RevertButton')
        RefreshButton     = $window.FindName('RefreshButton')
        SelectAllButton   = $window.FindName('SelectAllButton')
        SelectNoneButton  = $window.FindName('SelectNoneButton')
        PresetCombo       = $window.FindName('PresetCombo')
        RestorePointCheck = $window.FindName('RestorePointCheck')
        LogBox            = $window.FindName('LogBox')
        LogExpander       = $window.FindName('LogExpander')
        BusyOverlay       = $window.FindName('BusyOverlay')
        BusyText          = $window.FindName('BusyText')
        SubtitleText      = $window.FindName('SubtitleText')
        SystemText        = $window.FindName('SystemText')
        AdminText         = $window.FindName('AdminText')
        AdminBadge        = $window.FindName('AdminBadge')
    }

    $info = $script:Gui.SystemInfo
    $script:Gui.SubtitleText.Text = 'Windows 11 optimization'
    $script:Gui.SystemText.Text = '{0}  |  {1}  |  {2} GB RAM' -f $info.OSName, $info.CPU, $info.MemoryGB

    if ($info.IsAdmin) {
        $script:Gui.AdminText.Text = 'ADMINISTRATOR'
        $script:Gui.AdminText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#3FCF8E')
    } else {
        $script:Gui.AdminText.Text = 'NOT ELEVATED'
        $script:Gui.AdminText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#F5A524')
    }

    foreach ($name in (@('Overview') + (Get-SigmaCategory) + @('Maintenance', 'Backups'))) {
        $script:Gui.CategoryList.Items.Add($name) | Out-Null
    }

    $script:Gui.PresetCombo.Items.Add('Preset...') | Out-Null
    foreach ($preset in (Get-SigmaPreset)) {
        $script:Gui.PresetCombo.Items.Add($preset.Name) | Out-Null
    }
    $script:Gui.PresetCombo.SelectedIndex = 0

    Register-SigmaLogSink -Sink {
        param($line, $level)

        if (-not $script:Gui) { return }
        $script:Gui.LogBox.AppendText($line + [Environment]::NewLine)
        $script:Gui.LogBox.ScrollToEnd()
        Update-SigmaGuiFrame
    }

    $script:Gui.CategoryList.Add_SelectionChanged({
        $selected = $script:Gui.CategoryList.SelectedItem
        if ($selected) { Show-SigmaGuiCategory -Name $selected }
    })

    $script:Gui.SearchBox.Add_TextChanged({
        if ($script:Gui.Category -in @('Overview', 'Maintenance', 'Backups')) { return }
        Show-SigmaGuiCategory -Name $script:Gui.Category
    })

    $script:Gui.SelectAllButton.Add_Click({
        foreach ($id in $script:Gui.Checks.Keys) {
            if ($script:Gui.Checks[$id].IsEnabled) { $script:Gui.Checks[$id].IsChecked = $true }
        }
        Update-SigmaGuiSelection
    })

    $script:Gui.SelectNoneButton.Add_Click({
        foreach ($id in $script:Gui.Checks.Keys) { $script:Gui.Checks[$id].IsChecked = $false }
        Update-SigmaGuiSelection
    })

    $script:Gui.RefreshButton.Add_Click({
        Set-SigmaGuiBusy -Busy $true -Text 'Reading current state...'
        try {
            Show-SigmaGuiCategory -Name $script:Gui.Category
        } finally {
            Set-SigmaGuiBusy -Busy $false
        }
    })

    $script:Gui.ApplyButton.Add_Click({ Invoke-SigmaGuiBatch -Mode Apply })
    $script:Gui.RevertButton.Add_Click({ Invoke-SigmaGuiBatch -Mode Revert })

    $script:Gui.PresetCombo.Add_SelectionChanged({
        $name = $script:Gui.PresetCombo.SelectedItem
        if (-not $name -or $name -eq 'Preset...') { return }

        $preset = @(Get-SigmaPreset | Where-Object { $_.Name -eq $name }) | Select-Object -First 1
        if ($preset) { Set-SigmaGuiPreset -Key $preset.Key }
    })

    $window.Add_Closed({
        Clear-SigmaLogSinks
        $script:Gui = $null
    })

    $script:Gui.CategoryList.SelectedIndex = 0

    if (-not $info.IsAdmin) {
        Write-SigmaLog 'Running without administrator rights. System-wide tweaks will be refused.' -Level Warn
    }

    $window.ShowDialog() | Out-Null
}
