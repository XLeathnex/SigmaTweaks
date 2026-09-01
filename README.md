# SigmaTweaks

A Windows 11 optimization, privacy and debloat tool. One PowerShell script, a
proper interface, 96 tweaks and 13 maintenance actions — and every setting it
changes is recorded first, so you can put it back.

```
  ####  #  ####  #    #   #    ##
  #     #  #     ##  ##  # #  #  #     SigmaTweaks 1.0.0
  ####  #  # ##  # ## # #   # ####     Windows 11 optimization
     #  #  #  #  #    # #   # #  #
  ####  #  ####  #    # #   # #  #
```

## What it does

| Category | Tweaks | Examples |
| --- | --- | --- |
| Performance | 14 | Visual effects, foreground priority, Prefetch and SysMain on SSDs, Fast Startup, hibernation, reserved storage |
| Gaming | 8 | Game DVR off, fullscreen optimizations off, GPU scheduling, MMCSS priorities, mouse acceleration off |
| Privacy | 15 | Telemetry, advertising ID, activity history, Start menu ads, Cortana, web search, Recall, error reporting |
| Network | 4 | Nagle's algorithm, LLMNR, NetBIOS, Cloudflare DNS |
| Explorer | 16 | File extensions, the old right-click menu, taskbar layout, Widgets, Chat, dark mode |
| Services | 11 | Remote Registry, Print Spooler, Windows Search, Delivery Optimization |
| Updates | 5 | No forced restarts, no drivers through Windows Update, no update peer-sharing |
| Power | 4 | Ultimate Performance plan, USB selective suspend, sleep timers |
| Debloat | 19 | News, Weather, Solitaire, the Office stub, Clipchamp, consumer Teams, Xbox apps |

Plus maintenance jobs that are not settings: temp cleanup, Windows Update cache,
icon cache rebuild, DNS flush, network stack reset, SFC, DISM, TRIM.

The full list with descriptions is in [docs/TWEAKS.md](docs/TWEAKS.md).

## What it deliberately will not do

Plenty of "optimizer" tools ship switches that trade your security for a
placebo. SigmaTweaks has none of these, and will not be adding them:

- It does not disable Microsoft Defender, SmartScreen, tamper protection or the
  Windows Firewall.
- It does not disable UAC.
- It does not turn Windows Update off. The Updates category changes *when and
  how* updates arrive, never *whether* they do.
- It does not touch services that Windows needs to boot, log you in, reach the
  network or stay patched. Those are on a hard-coded protected list in
  `src/Core/Services.ps1` and are refused even if a tweak asks for them.
- It does not download or run anything from the internet.

## Requirements

- Windows 11 (most tweaks also work on Windows 10; ones that do not are marked
  N/A automatically and skipped)
- Windows PowerShell 5.1, which ships with Windows — or PowerShell 7
- Administrator rights for system-wide tweaks. The script asks for elevation
  itself; per-user tweaks work without it.

## Quick start

Download or clone the repository, then double-click **`SigmaTweaks.bat`**.

```powershell
git clone https://github.com/XLeathnex/SigmaTweaks.git
cd SigmaTweaks
.\SigmaTweaks.bat
```

If you would rather run the script directly, PowerShell's execution policy will
block an unsigned downloaded script unless you tell it not to:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SigmaTweaks.ps1
```

## Using the interface

- Pick a category on the left. Each tweak shows its risk level and whether it is
  currently **applied**, **off**, **partial** (some of its values are set) or
  **N/A** (it does not apply to this machine — Windows 10, or a hard disk).
- Tick what you want and press **Apply selected**. **Revert selected** puts the
  stock Windows values back.
- The **Preset** dropdown ticks the boxes belonging to a preset on the page you
  are looking at. Switch category and pick it again to select the rest.
- **Create restore point first** is on by default. Leave it on.
- The **Backups** page lists every snapshot taken so far, with a Restore button.
- Open the **Activity log** at the bottom to watch exactly what is being changed.

## Command line

Everything the interface does is available without it.

```powershell
# See what is available
.\SigmaTweaks.ps1 -List
.\SigmaTweaks.ps1 -ListPresets
.\SigmaTweaks.ps1 -ListActions

# See what is currently applied on this machine
.\SigmaTweaks.ps1 -Status

# Dry run: show every change a preset would make, without making it
.\SigmaTweaks.ps1 -Preset recommended -WhatIf

# Apply a preset, taking a restore point first
.\SigmaTweaks.ps1 -Preset recommended -RestorePoint

# Apply or revert individual tweaks; wildcards work
.\SigmaTweaks.ps1 -Apply perf.visualfx,explorer.fileextensions
.\SigmaTweaks.ps1 -Apply 'privacy.*'
.\SigmaTweaks.ps1 -Revert 'gaming.*'

# Save this machine's applied tweaks, then reproduce them elsewhere
.\SigmaTweaks.ps1 -ExportProfile .\my-setup.json
.\SigmaTweaks.ps1 -ImportProfile .\my-setup.json

# Maintenance
.\SigmaTweaks.ps1 -RunAction action.cleantemp
.\SigmaTweaks.ps1 -ListBackups
.\SigmaTweaks.ps1 -RestoreBackup "$env:LOCALAPPDATA\SigmaTweaks\backups\20260901_120000_apply.json"
```

`Get-Help .\SigmaTweaks.ps1 -Detailed` documents every parameter.

## Presets

| Key | Tweaks | What it is for |
| --- | --- | --- |
| `recommended` | 36 | The safe default: reversible settings only, no apps removed |
| `performance` | 31 | Adds the settings that trade features or power draw for speed |
| `privacy` | 20 | Every telemetry and tracking setting SigmaTweaks knows about |
| `gaming` | 21 | Latency and frame-time work, plus a power plan that stops parking cores |
| `laptop` | 30 | Recommended, minus everything that costs battery life |
| `debloat` | 14 | Removes the pre-installed Store apps most people never open |

Presets are plain JSON in `presets/`. Copy one, edit the id list, drop it back in
the folder and it appears in the dropdown.

## How reverting works

Two independent mechanisms, because they fail in different ways:

**Declared defaults.** Every tweak states the stock Windows value alongside the
one it writes. *Revert selected* writes those defaults back. This works even on
a machine that has never run SigmaTweaks.

**Snapshots.** Before any batch is applied, SigmaTweaks reads the *current*
value of everything that batch is about to touch and writes it to
`%LOCALAPPDATA%\SigmaTweaks\backups\<timestamp>_apply.json`. Restoring that
snapshot puts back what was really there, including customisations that differ
from the Windows defaults. This is the accurate one, and it is what the Backups
page uses.

Store app removal is the exception: nothing can put an uninstalled app back
except the Microsoft Store. Those tweaks are marked *cannot be undone* in the
interface and refuse to revert rather than pretending.

Logs live in `%LOCALAPPDATA%\SigmaTweaks\logs`, ten runs deep.

## Adding your own tweak

Drop a file in `src/Tweaks/` that emits an array of hashtables. Most tweaks are
purely declarative — list what changes and the engine derives apply, revert and
state detection from it:

```powershell
@{
    Id              = 'explorer.mytweak'
    Name            = 'Short label for the list'
    Category        = 'Explorer'
    Description     = 'A sentence or two on what changes and what it costs.'
    Risk            = 'Low'              # Low | Medium | High
    Recommended     = $true              # include in the recommended preset
    RequiresAdmin   = $false             # HKCU-only tweaks do not need elevation
    RestartExplorer = $true
    Registry        = @(
        # Default is what Revert writes. $null means "delete the value".
        @{ Path = 'HKCU:\Software\...'; Name = 'Thing'; Type = 'DWord'; Value = 1; Default = 0 }
    )
}
```

`Services`, `ScheduledTasks` and `Appx` entries work the same way. Anything that
cannot be expressed as a list of values supplies `Apply`, `Revert` and `Test`
scriptblocks instead — see `perf.hibernation` or `net.nagle` for examples.

The catalog is validated on load: a tweak missing a required field, or a
registry entry with no `Default` and no custom `Test`, is reported and skipped
rather than half-applied.

## Project layout

```
SigmaTweaks.ps1          entry point: argument handling, elevation, dispatch
SigmaTweaks.bat          double-click launcher
src/Core/                logging, registry, services, appx, backups, the engine
src/Tweaks/              the tweak catalog, one file per category
src/Actions/             one-shot maintenance jobs
src/UI/                  MainWindow.xaml and the WPF code that drives it
presets/                 JSON tweak lists
docs/TWEAKS.md           generated reference for every tweak
```

## Troubleshooting

**"running scripts is disabled on this system"** — use `SigmaTweaks.bat`, or add
`-ExecutionPolicy Bypass` as shown above. SigmaTweaks never changes your
execution policy for you.

**SmartScreen warns about the batch file** — expected for any unsigned script
downloaded from the internet. Read the source; it is 20 lines.

**A tweak shows "partial"** — some of its values are set and some are not,
usually because it was applied before an update reset one of them. Applying it
again fixes it.

**A tweak shows "N/A"** — it does not apply to this machine. Windows 11-only
tweaks on Windows 10, or SSD-only tweaks on a hard disk. They are skipped rather
than failed.

**Something broke** — restore the newest snapshot from the Backups page, or roll
back to the restore point taken before the batch.

## License

MIT. See [LICENSE](LICENSE).

SigmaTweaks changes operating system settings. It backs them up first and it
avoids the genuinely dangerous ones, but you are still the one deciding what to
change on your machine. Read the descriptions.
