# SigmaTweaks

A Windows 11 optimization, privacy and debloat tool. Rust backend, Tauri
desktop shell, 119 tweaks and 13 maintenance actions — and every setting it
changes is recorded first, so you can put it back.

It scans the machine on startup and tells you what is **already** done, whether
you did it here, with another tool, or by hand.

## What it does

| Category | Tweaks | Examples |
| --- | --- | --- |
| Performance | 14 | Visual effects, foreground priority, Prefetch and SysMain on SSDs, Fast Startup, hibernation, reserved storage |
| Gaming | 11 | System-wide timer resolution, windowed-game optimizations, Game DVR off, fullscreen optimizations off, GPU scheduling, MMCSS priorities, mouse acceleration off |
| Productivity | 10 | Clipboard history, long paths, symlinks without admin, a predictable Alt+Tab, no Sticky Keys prompt, no suggestion toasts |
| Privacy | 15 | Telemetry, advertising ID, activity history, Start menu ads, Cortana, web search, Recall, error reporting |
| Network | 4 | Nagle's algorithm, LLMNR, NetBIOS, Cloudflare DNS |
| Explorer | 16 | File extensions, the old right-click menu, taskbar layout, Widgets, Chat, dark mode |
| Services | 11 | Remote Registry, Print Spooler, Windows Search, Delivery Optimization |
| Updates | 5 | No forced restarts, no drivers through Windows Update, no update peer-sharing |
| Power | 4 | Ultimate Performance plan, USB selective suspend, sleep timers |
| Debloat | 29 | News, Weather, Solitaire, the Office stub, Clipchamp, consumer Teams, Xbox apps, new Outlook, Dev Home, Widgets, OEM promo stubs |

Plus maintenance jobs that are not settings: temp cleanup, Windows Update
cache, icon cache rebuild, DNS flush, network stack reset, SFC, DISM, TRIM.

The full list is in [docs/TWEAKS.md](docs/TWEAKS.md).

## Detecting what is already done

A tweaking tool that cannot see the current state is guesswork, so detection is
treated as a first-class feature rather than a status icon:

- **The whole catalog is scanned on startup**, and the sidebar shows `applied /
  total` per category. Store packages and scheduled tasks come from two cached
  snapshots, so 119 tweaks cost two process launches rather than one per item.
- **Equivalent values count.** Other tools and the Windows UI often reach the
  same end state through a different number. `Win32PrioritySeparation` is
  `0x26` here, but `0x28` and `0x2A` are equally short-quantum; telemetry set
  to Basic in Settings lands on `1` where the policy writes `0`. Each of those
  reads as *applied* rather than *off*. Those values are recognised, never
  written, and a test rejects an "equivalent" that is really the stock default.
- **Partial is explained.** A tweak that sets four values and finds three shows
  "3 of 4 already set" rather than an unlabelled amber pill.
- **Filters**: All, Not applied, Already applied, Recommended.
- **Presets skip what is done.** Picking one selects only what is actually
  missing and says so: *"Preset Productivity: 19 selected, 4 already applied."*

## What it deliberately will not do

Plenty of "optimizer" tools ship switches that trade your security for a
placebo. SigmaTweaks has none of these, and will not be adding them:

- It does not disable Microsoft Defender, SmartScreen, tamper protection or the
  Windows Firewall. A unit test fails the build if a tweak ever starts writing
  to one of those settings.
- It does not disable UAC.
- It does not turn Windows Update off. The Updates category changes *when and
  how* updates arrive, never *whether* they do.
- It does not touch services Windows needs to boot, sign you in, reach the
  network or stay patched, and it does not remove Store packages the shell or
  the Store itself depend on. Both lists live in `src-tauri/src/protected.rs`
  and are enforced at runtime *and* asserted against the catalog in tests.
- It does not download or run anything from the internet.

There is exactly **one** setting that lowers a security boundary, and it is
deliberate: `gaming.memoryintegrity` turns off hypervisor-enforced code
integrity (HVCI), which is worth roughly 5-10% of your frame rate and is the
mitigation that stops a vulnerable signed driver being used to load unsigned
kernel code. Microsoft leaves it off on most upgrade installs, so this returns
the machine to that state rather than below it. It is High risk, it says all of
this in its own description, and a test keeps it out of every preset — you have
to tick it yourself.

## Requirements

- Windows 11 (most tweaks also work on Windows 10; the rest are marked N/A
  automatically and skipped)
- Administrator rights for system-wide tweaks. The header badge relaunches the
  app elevated; per-user tweaks work without it.

Nothing else — the app is a single executable with the catalog compiled in. It
uses the WebView2 runtime that ships with Windows 11.

## Building

```bash
npm install
npm run start      # dev build with hot reload
npm run bundle     # NSIS and MSI installers in src-tauri/target/release/bundle
```

Building the installers needs a Windows machine with the Rust MSVC toolchain
and the Visual Studio C++ build tools. Everything else — typechecking, the Rust
test suite, and `cargo check --target x86_64-pc-windows-msvc` — runs on any
host.

## Using it

- Pick a category on the left. The `n/total` beside each one is how much of it
  is already in place. Each tweak shows **Applied**, **Partial** (with a count),
  **N/A** (does not apply here) or nothing at all when it is simply off — the
  common case is shown by absence rather than by a badge on every row.
- Low risk is likewise unmarked; only Medium and High say so.
- Tick what you want and press **Apply selected**. **Revert selected** writes
  the stock Windows values back.
- Selection is global, not per-page: a preset ticks everything it covers across
  every category, and Apply runs it as one batch.
- **Create restore point first** is on by default. Leave it on.
- The **Backups** page lists every snapshot taken so far, with a Restore button.
- The **Activity log** at the bottom streams what the backend is doing, live.

## Presets

| Key | Tweaks | What it is for |
| --- | --- | --- |
| `recommended` | 42 | The safe default: reversible settings only, no apps removed |
| `performance` | 33 | Adds the settings that trade features or power draw for speed |
| `productivity` | 23 | Friction removal: clipboard history, long paths, a predictable shell |
| `privacy` | 20 | Every telemetry and tracking setting SigmaTweaks knows about |
| `gaming` | 24 | Timer resolution, frame pacing, capture off, a plan that stops parking cores |
| `laptop` | 34 | Recommended, minus everything that costs battery life |
| `debloat` | 21 | Removes the pre-installed Store apps most people never open |

Presets live in `src-tauri/resources/presets.json` and are compiled into the
binary. A test asserts that every id in every preset resolves, and that nothing
irreversible sneaks into `recommended`.

## How reverting works

Two independent mechanisms, because they fail in different ways:

**Declared defaults.** Every tweak states the stock Windows value next to the
one it writes. Revert writes those defaults back, and works on a machine that
has never run SigmaTweaks.

**Snapshots.** Before any batch, the *current* value of everything it is about
to touch is read and written to
`%LOCALAPPDATA%\SigmaTweaks\backups\<timestamp>_apply.json`. Restoring that
snapshot puts back what was really there, including customisations that differ
from Microsoft's defaults. This is the accurate one, and it is what the Backups
page uses.

Store app removal is the exception: nothing can reinstall an app except the
Store. Those tweaks are marked one-way, and refuse to revert rather than
pretending.

## Architecture

```
ui/                     TypeScript frontend: a view over the catalog plus a selection set
  main.ts               rendering, selection, batch flow
  api.ts                typed wrappers over the Tauri command bridge
src-tauri/
  resources/            catalog.json and presets.json, compiled into the binary
  src/
    model.rs            the tweak schema
    catalog.rs          embedded catalog, id resolution, applicability rules
    codec.rs            registry value encoding, decoding, comparison
    inventory.rs        cached package and scheduled-task snapshots
    parse.rs            schtasks CSV and package-pattern parsing
    protected.rs        the services and packages that are never touched
    engine.rs           apply, revert and state detection
    registry.rs         winreg wrapper
    services.rs         service startup types and scheduled tasks
    appx.rs             Store app removal
    custom.rs           the changes that are not "write this value there"
    backup.rs           snapshots
    maintenance.rs      one-shot jobs
    sysinfo.rs          host facts
    commands.rs         the Tauri bridge
docs/TWEAKS.md          generated reference
```

A tweak is **data**, not code. `catalog.json` lists the registry values,
services, scheduled tasks and packages a tweak changes, each with the stock
value to revert to:

```json
{
  "id": "explorer.fileextensions",
  "name": "Show file extensions",
  "category": "Explorer",
  "description": "Stops Explorer hiding the extension of known file types...",
  "risk": "low",
  "recommended": true,
  "requires_admin": false,
  "restart_explorer": true,
  "actions": [
    {
      "kind": "registry",
      "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
      "name": "HideFileExt",
      "value_type": "dword",
      "value": 0,
      "default": 1
    }
  ]
}
```

An action may also carry `accepts`: extra values that read as applied but are
never written, which is how detection recognises the same change made by
something else.

Apply, revert and "is it on?" are three readings of that one list, so they
cannot drift apart. `default` is a required field: a registry action that omits
it fails to deserialise, which means a tweak that cannot be reverted fails to
compile rather than shipping. The eleven changes that genuinely cannot be
expressed this way — Nagle, hibernation, the power schemes — name a
`custom` op implemented in `custom.rs`.

## Troubleshooting

**"NOT ELEVATED" in the header** — click it. The app relaunches through UAC.

**A tweak shows "partial"** — some of its values are set and some are not,
usually because a Windows update reset one. Applying it again fixes it.

**A tweak shows "N/A"** — it does not apply to this machine. Windows 11-only
tweaks on Windows 10, or SSD-only tweaks on a hard disk. An *unknown* disk type
does not block anything; only a confirmed hard disk does.

**Something broke** — restore the newest snapshot from the Backups page, or
roll back to the restore point taken before the batch.

## License

MIT. See [LICENSE](LICENSE).

SigmaTweaks changes operating system settings. It records them first and avoids
the genuinely dangerous ones, but you are still the one deciding what to change
on your machine. Read the descriptions.
