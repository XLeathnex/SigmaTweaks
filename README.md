# SigmaTweaks

A Windows 11 optimization, privacy and debloat tool. Rust backend, Tauri
desktop shell, 96 tweaks and 13 maintenance actions — and every setting it
changes is recorded first, so you can put it back.

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

Plus maintenance jobs that are not settings: temp cleanup, Windows Update
cache, icon cache rebuild, DNS flush, network stack reset, SFC, DISM, TRIM.

The full list is in [docs/TWEAKS.md](docs/TWEAKS.md).

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

- Pick a category on the left. Each tweak shows its risk and whether it is
  currently **applied**, **off**, **partial** (some of its values are set) or
  **N/A** (it does not apply to this machine — Windows 10, or a hard disk).
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
| `recommended` | 36 | The safe default: reversible settings only, no apps removed |
| `performance` | 31 | Adds the settings that trade features or power draw for speed |
| `privacy` | 20 | Every telemetry and tracking setting SigmaTweaks knows about |
| `gaming` | 21 | Latency and frame-time work, plus a power plan that stops parking cores |
| `laptop` | 30 | Recommended, minus everything that costs battery life |
| `debloat` | 14 | Removes the pre-installed Store apps most people never open |

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
