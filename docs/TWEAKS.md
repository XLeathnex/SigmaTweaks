# Tweak reference

Generated from the catalog in `src/Tweaks`. 96 tweaks across 9 categories.

Every id below can be passed to `-Apply`, `-Revert` or matched with a wildcard,
for example `-Apply 'privacy.*'`. Risk is about how likely the change is to get in
your way, not how likely it is to break something:

| Risk | Meaning |
| --- | --- |
| Low | Cosmetic or clearly beneficial. Safe to apply without thinking about it. |
| Medium | A real trade-off. Read the description before ticking it. |
| High | Removes functionality you may depend on. Only pick it deliberately. |

## Performance (14)

| Id | Risk | Notes | What it does |
| --- | --- | --- | --- |
| `perf.visualfx` | Low | explorer, no admin | **Adjust visual effects for performance** Switches the Performance Options dialog to "Adjust for best performance", turning off window animations, shadows and fades. The single biggest perceived-latency win on low-end hardware. |
| `perf.transparency` | Low | no admin | **Disable transparency effects** Turns off the acrylic/mica blur behind the Start menu, taskbar and settings surfaces. Saves a small but constant amount of GPU work. |
| `perf.menudelay` | Low | restart, no admin | **Remove menu show delay** Drops the 400 ms delay before submenus open. Menus feel instant; nothing else changes. |
| `perf.startupdelay` | Low | no admin | **Remove startup program delay** Windows holds startup apps back for about ten seconds after logon to let the desktop settle. This removes that wait. |
| `perf.priorityseparation` | Low | restart | **Favour foreground applications** Sets Win32PrioritySeparation to short, variable quanta with a 3:1 foreground boost. Helps the window you are using stay responsive while something heavy runs behind it. |
| `perf.prefetch` | Medium | restart, SSD only | **Disable Prefetch (SSD only)** Prefetch pre-loads boot and application data to hide seek latency. On an SSD there is no seek latency to hide, so it is pure write amplification. |
| `perf.sysmain` | Medium | SSD only | **Disable SysMain / Superfetch (SSD only)** SysMain caches frequently used apps into RAM ahead of time. On an SSD with 16 GB or more this mostly costs background disk I/O. Leave it on if you are on a hard disk. |
| `perf.faststartup` | Low | restart | **Disable Fast Startup** Fast Startup hibernates the kernel on shutdown. It shortens boot but leaves drivers in a stale state, breaks dual-boot filesystem access and makes "shut down" not really shut down. |
| `perf.waittokill` | Low | restart | **Shorten service shutdown timeout** Cuts the grace period Windows gives services during shutdown from 5 s to 3 s. Shortens shutdown; anything slower than 3 s is killed rather than asked twice. |
| `perf.powerthrottling` | Medium | restart | **Disable power throttling** Stops Windows from parking background processes onto efficiency cores and lower clocks. Helps sustained background work; costs battery life on a laptop. |
| `perf.backgroundapps` | Low | no admin | **Disable background apps** Prevents Store apps from running and refreshing while you are not using them. Live tiles and app notifications stop updating in the background. |
| `perf.lastaccess` | Low | - | **Disable NTFS last-access timestamps** NTFS writes a timestamp every time a file is read. Turning that off removes a metadata write from every read. Backup tools that key on last-access time are rare, but check yours. |
| `perf.hibernation` | Medium | restart | **Disable hibernation** Deletes hiberfil.sys, reclaiming roughly 40% of your RAM size in disk space. Also disables Fast Startup, which depends on it. Do not use this on a laptop you suspend to disk. |
| `perf.reservedstorage` | Low | - | **Disable reserved storage** Windows reserves about 7 GB for update staging. Disabling it returns that space now; feature updates will instead need free space at install time. |

## Gaming (8)

| Id | Risk | Notes | What it does |
| --- | --- | --- | --- |
| `gaming.gamemode` | Low | no admin | **Enable Game Mode** Lets Windows prioritise the foreground game and hold back background work such as Windows Update and driver installs while you play. |
| `gaming.gamedvr` | Low | - | **Disable Game DVR background recording** Game DVR keeps a rolling capture buffer running behind every game, which costs frames on mid-range GPUs. Manual recording and screenshots through Game Bar stop working. |
| `gaming.gamebarpopup` | Low | no admin | **Stop the Game Bar popup** Stops the "Do you want to open Game Bar?" panel appearing when a controller button is pressed or a game launches. |
| `gaming.fullscreenoptimizations` | Medium | no admin | **Disable fullscreen optimizations** Forces true exclusive fullscreen instead of the borderless-window path Windows substitutes by default. Usually lowers input latency; a few games alt-tab more slowly afterwards. |
| `gaming.hags` | Medium | restart | **Enable hardware-accelerated GPU scheduling** Hands VRAM scheduling to the GPU instead of the CPU, shaving a little latency on supported cards. Needs a driver that supports it; the setting is ignored otherwise. |
| `gaming.mmcss` | Medium | restart | **Tune multimedia scheduling for games** Lowers the share of CPU time MMCSS reserves for background tasks from 20% to 10%, lifts the network throttle that caps packet rates during multimedia playback, and raises the priority of the Games scheduling profile. |
| `gaming.mouseaccel` | Low | no admin | **Disable mouse acceleration** Turns off "Enhance pointer precision" so cursor distance depends only on how far the mouse moved, not how fast. Makes aim consistent between sessions. |
| `gaming.xboxservices` | Medium | - | **Disable Xbox Live services** Blocks the Xbox Live auth, save-sync and networking services from starting at all. Only pick this if you never use Game Pass, the Xbox app or an Xbox controller over Bluetooth - those all need these services and cannot start them on demand once disabled. |

## Privacy (15)

| Id | Risk | Notes | What it does |
| --- | --- | --- | --- |
| `privacy.telemetry` | Low | - | **Disable diagnostic data collection** Sets the diagnostic data policy to the lowest level, stops the Connected User Experiences and Telemetry service, and disables the Compatibility Appraiser and CEIP tasks that feed it. Home and Pro still send basic required data; only Enterprise and Education honour a full zero. |
| `privacy.advertisingid` | Low | - | **Disable the advertising ID** Stops apps from reading the per-user advertising identifier used to correlate you across Store apps. Ads still appear; they stop being personalised. |
| `privacy.tailored` | Low | no admin | **Disable tailored experiences** Stops Windows from using your diagnostic data to personalise tips, ads and recommendations in the shell. |
| `privacy.suggestions` | Low | no admin | **Remove suggestions, tips and Start menu ads** Clears the Content Delivery Manager flags behind "suggested" Start menu entries, lock screen adverts, silently installed promo apps and the "Get even more out of Windows" nag. |
| `privacy.activityhistory` | Low | - | **Disable activity history** Stops Windows recording which apps and documents you opened, and stops uploading that timeline to your Microsoft account. |
| `privacy.apptracking` | Low | no admin | **Stop tracking app launches** Windows counts how often you start each program to order the "Most used" list. This turns that counting off. |
| `privacy.cortana` | Low | - | **Disable Cortana** Blocks Cortana through policy. Local file and settings search keep working. |
| `privacy.websearch` | Low | explorer | **Remove web results from Start menu search** Search stops querying Bing and stops sending your typed query to Microsoft. Only local results are returned, which also makes search noticeably faster. |
| `privacy.copilot` | Low | Win11 | **Disable Windows Copilot** Turns off the Copilot side panel and removes its taskbar entry through policy. |
| `privacy.recall` | Low | Win11 | **Disable Recall snapshots** Blocks the Windows AI feature that periodically screenshots everything you do and indexes it locally. Only present on Copilot+ hardware, but the policy is harmless elsewhere. |
| `privacy.feedback` | Low | no admin | **Stop feedback requests** Stops Windows asking how likely you are to recommend it, and disables the feedback upload tasks. |
| `privacy.speech` | Low | - | **Disable online speech recognition** Stops voice input being sent to Microsoft for processing. Offline speech recognition still works. |
| `privacy.inking` | Low | no admin | **Disable inking and typing personalisation** Stops Windows building a personal dictionary from what you type and write, and stops harvesting contact names for it. |
| `privacy.location` | Medium | - | **Deny location access** Sets the system-wide location consent to Deny and stops the geolocation service. Maps, Weather and "find my device" stop knowing where you are. |
| `privacy.errorreporting` | Low | - | **Disable Windows Error Reporting** Stops crash dumps being uploaded to Microsoft. Local crash logs in Event Viewer are unaffected. |

## Network (4)

| Id | Risk | Notes | What it does |
| --- | --- | --- | --- |
| `net.nagle` | Medium | restart | **Disable Nagle's algorithm** Nagle batches small outbound packets to save bandwidth, which adds up to 200 ms of latency to the tiny packets games and voice chat send. Disabling it trades a little extra overhead for lower latency. |
| `net.llmnr` | Low | - | **Disable LLMNR** Link-Local Multicast Name Resolution broadcasts any name your machine fails to resolve onto the local network, where anyone can answer it. Turning it off removes a well-known credential-relay vector and a little broadcast noise. DNS is unaffected. |
| `net.netbios` | Medium | restart | **Disable NetBIOS over TCP/IP** Switches every adapter off NetBIOS name resolution, another legacy broadcast protocol that answers for names DNS could not resolve. Only turn this on if nothing on your network still browses shares by NetBIOS name. |
| `net.dnscloudflare` | Medium | - | **Use Cloudflare DNS (1.1.1.1)** Points every active adapter at 1.1.1.1 and 1.0.0.1 instead of whatever your router hands out. Usually faster to resolve than an ISP resolver. Reverting hands DNS back to DHCP - if you had DNS servers set by hand, note them down first. |

## Explorer (16)

| Id | Risk | Notes | What it does |
| --- | --- | --- | --- |
| `explorer.fileextensions` | Low | explorer, no admin | **Show file extensions** Stops Explorer hiding the extension of known file types. Worth doing on any machine: it is the difference between seeing invoice.pdf and invoice.pdf.exe. |
| `explorer.hiddenfiles` | Low | explorer, no admin | **Show hidden files** Shows files and folders marked hidden. Protected operating system files stay hidden. |
| `explorer.launchtothispc` | Low | explorer, no admin | **Open Explorer to This PC** Makes new Explorer windows start at This PC instead of Home / Quick access. |
| `explorer.quickaccessrecent` | Low | explorer, no admin | **Hide recent files and frequent folders** Stops Quick access listing recently opened files and frequently used folders, so a shared screen does not advertise what you have been working on. |
| `explorer.compactmode` | Low | explorer, Win11, no admin | **Use compact spacing in Explorer** Restores the tighter Windows 10 row spacing in file lists, fitting noticeably more per screen. |
| `explorer.taskbarleft` | Low | explorer, Win11, no admin | **Align the taskbar to the left** Moves Start and the pinned icons back to the left edge. |
| `explorer.widgets` | Low | explorer, Win11 | **Remove Widgets from the taskbar** Hides the weather and news panel and blocks it by policy, which also stops its background feed process. |
| `explorer.chat` | Low | explorer, Win11, no admin | **Remove Chat from the taskbar** Hides the consumer Teams chat button. Teams itself is untouched. |
| `explorer.taskview` | Low | explorer, no admin | **Remove the Task View button** Hides the Task View icon. Win+Tab still works. |
| `explorer.searchicon` | Low | explorer, Win11, no admin | **Shrink the taskbar search box to an icon** Replaces the wide search field with a single magnifier icon, giving the taskbar back to your pinned apps. |
| `explorer.endtask` | Low | explorer, Win11, no admin | **Add End Task to the taskbar right-click menu** Lets you kill a hung app straight from its taskbar button instead of opening Task Manager. |
| `explorer.darkmode` | Low | explorer, no admin | **Use the dark theme** Switches both the shell and apps to dark mode. |
| `explorer.shortcutsuffix` | Low | - | **Drop the " - Shortcut" suffix** New shortcuts are named after their target instead of gaining a suffix. Existing shortcuts keep their current names. |
| `explorer.verbosestatus` | Low | - | **Show detailed startup and shutdown messages** Replaces the spinner during logon and shutdown with the name of whatever is actually running. Useful when something is holding up boot. |
| `explorer.numlock` | Low | - | **Turn NumLock on at sign-in** Enables NumLock on the lock screen and for new sessions, so typing a numeric PIN works straight away. |
| `explorer.classiccontextmenu` | Low | explorer, Win11, no admin | **Restore the full right-click menu** Brings back the Windows 10 context menu so you no longer have to click "Show more options" to reach the entries your other programs add. |

## Services (11)

| Id | Risk | Notes | What it does |
| --- | --- | --- | --- |
| `svc.remoteregistry` | Low | - | **Disable Remote Registry** Stops other machines editing this one's registry over the network. Almost nothing on a home or workstation setup needs it. |
| `svc.remoteassistance` | Low | - | **Disable Remote Assistance** Refuses inbound Remote Assistance invitations. Quick Assist and Remote Desktop are separate features and keep working. |
| `svc.fax` | Low | - | **Disable the Fax service** Turns off fax send and receive. |
| `svc.retaildemo` | Low | - | **Disable Retail Demo** The in-store demo mode service. It has no purpose outside a shop display. |
| `svc.wmpnetwork` | Low | - | **Disable Windows Media Player network sharing** Stops the service that streams your media library to other devices on the network. |
| `svc.mapsbroker` | Low | - | **Disable the offline maps downloader** Stops background downloads of offline map data. The Maps app still works online. |
| `svc.spooler` | Medium | - | **Disable the Print Spooler** Printing stops working entirely, including "print to PDF". Pick this only on a machine with no printer; the spooler has a long history of privilege-escalation bugs, so switching it off on a printer-less box is worth doing. |
| `svc.wsearch` | High | - | **Disable Windows Search indexing** Stops the indexer, which removes a steady background disk and CPU load. In exchange, Start menu and Explorer searches fall back to slow live scans, and Outlook search degrades badly. Worth it on a weak machine, painful on a busy one. |
| `svc.deliveryoptimization` | Low | - | **Stop Delivery Optimization from starting itself** Sets the peer-to-peer update cache service to manual start so it stops idling in the background. Windows Update starts it on demand when it genuinely needs it. |
| `svc.touchkeyboard` | Medium | - | **Disable the touch keyboard service** Turns off the on-screen keyboard and handwriting panel service. This also disables the emoji picker (Win+.), so skip it if you use that. |
| `svc.parentalcontrols` | Medium | - | **Disable Family Safety** Turns off the parental-controls enforcement service. Do not use this on a machine where a child account has screen-time or content limits. |

## Updates (5)

| Id | Risk | Notes | What it does |
| --- | --- | --- | --- |
| `update.noautoreboot` | Low | - | **Never restart automatically while signed in** Windows will still install updates, but it will wait for you to restart instead of rebooting out from under an open session. |
| `update.nodrivers` | Low | - | **Do not deliver drivers through Windows Update** Keeps Windows Update from replacing your GPU, audio or chipset drivers with its own generic versions. Install drivers from the vendor instead. |
| `update.deliveryoptimization` | Low | - | **Stop sharing updates with other PCs** Sets Delivery Optimization to download from Microsoft only, instead of also uploading update chunks to other machines on the internet. |
| `update.noautoappupdate` | Medium | - | **Stop the Store updating apps automatically** Store apps update only when you ask. Handy on a metered connection; remember to update by hand now and then. |
| `update.notifybeforedownload` | High | - | **Ask before downloading updates** Windows notifies you that updates are available and waits for you to start the download. Updates you never approve are never installed, so only choose this if you will actually check. |

## Power (4)

| Id | Risk | Notes | What it does |
| --- | --- | --- | --- |
| `power.ultimateperformance` | Medium | - | **Enable the Ultimate Performance power plan** Unhides the hidden Ultimate Performance scheme and makes it active. It removes the micro-latencies that come from parking cores and ramping clocks. On a laptop this will noticeably shorten battery life. |
| `power.usbselectivesuspend` | Low | - | **Disable USB selective suspend** Stops Windows powering down idle USB ports. Fixes mice, controllers and audio interfaces that drop out after a few seconds of inactivity, at a small cost in idle power draw. |
| `power.neversleepac` | Low | - | **Never sleep while plugged in** Sets the sleep and hibernate timers to Never on AC power. The display still turns off on its own schedule. |
| `power.hiddenplans` | Low | restart | **Unhide all power plans in Control Panel** Makes High Performance and the other schemes Windows hides on modern standby laptops selectable again. |

## Debloat (19)

| Id | Risk | Notes | What it does |
| --- | --- | --- | --- |
| `debloat.bingnews` | Low | one-way | **Remove Microsoft News** Removes the Bing-powered News app that feeds the Widgets panel. |
| `debloat.bingweather` | Low | one-way | **Remove MSN Weather** Removes the Weather app. |
| `debloat.solitaire` | Low | one-way | **Remove Microsoft Solitaire Collection** Removes the bundled card games and their ads. |
| `debloat.officehub` | Low | one-way | **Remove the Office / Microsoft 365 stub** Removes the "Get Office" promotional launcher. A real Office or Microsoft 365 installation is a separate desktop program and is not affected. |
| `debloat.gethelp` | Low | one-way | **Remove Get Help and Tips** Removes the support-chat app and the "Tips" tour app. |
| `debloat.feedbackhub` | Low | one-way | **Remove Feedback Hub** Removes the app used to send feedback to Microsoft. |
| `debloat.maps` | Low | one-way | **Remove Maps** Removes the Windows Maps app. |
| `debloat.people` | Low | one-way | **Remove People** Removes the People contacts app. Mail and Calendar keep their own contact handling. |
| `debloat.clipchamp` | Low | one-way | **Remove Clipchamp** Removes the bundled video editor. |
| `debloat.teams` | Low | one-way | **Remove consumer Teams / Chat** Removes the personal Teams app wired to the taskbar Chat button. Teams for work, installed separately, is not affected. |
| `debloat.yourphone` | Low | one-way | **Remove Phone Link** Removes the app that mirrors an Android or iPhone onto the desktop. |
| `debloat.zunemedia` | Medium | one-way | **Remove Media Player and Movies & TV** Removes the built-in media apps. Only do this if you have another player installed - nothing else on a clean install opens video files. |
| `debloat.xboxapps` | Medium | one-way | **Remove the Xbox apps and overlay** Removes the Xbox console companion, the Game Bar overlay and its speech overlay. The Xbox identity provider is kept, so games that sign in with a Microsoft account still work. |
| `debloat.mixedreality` | Low | one-way | **Remove Mixed Reality Portal and 3D Viewer** Removes two leftovers from the Windows Mixed Reality era. |
| `debloat.skype` | Low | one-way | **Remove Skype** Removes the pre-installed Skype client. |
| `debloat.powerautomate` | Low | one-way | **Remove Power Automate Desktop** Removes the bundled desktop automation designer. |
| `debloat.todos` | Low | one-way | **Remove Microsoft To Do** Removes the To Do task app. |
| `debloat.quickassist` | Low | one-way | **Remove Quick Assist** Removes the remote-help tool. Worth removing on a machine whose user might be talked into starting it by a phone scammer. |
| `debloat.copilotapp` | Low | one-way, Win11 | **Remove the Copilot app** Removes the Copilot Store app. Pair this with the Copilot policy tweak under Privacy to keep it from coming back through the shell. |

## Maintenance actions

Run one with `-RunAction <id>`, or from the Maintenance page in the interface.

| Id | Action | What it does |
| --- | --- | --- |
| `action.restorepoint` | Create a restore point | Takes a System Restore checkpoint you can roll back to from Windows Recovery. |
| `action.systemprotection` | Turn on System Protection | Enables System Restore for the system drive. Restore points cannot be taken at all until this is on, and Windows ships with it off on many OEM installs. It reserves a few percent of the drive. |
| `action.cleantemp` | Clean temporary files | Empties the user and system temp folders, the Windows prefetch cache and leftover Windows Update download files. |
| `action.recyclebin` | Empty the Recycle Bin | Permanently deletes everything currently in the Recycle Bin on every drive. |
| `action.updatecache` | Clear the Windows Update cache | Stops Windows Update, deletes its downloaded package cache and starts it again. Fixes updates that fail repeatedly and reclaims several gigabytes. |
| `action.storecache` | Reset the Microsoft Store cache | Runs wsreset, which clears the Store cache without touching installed apps. Fixes downloads that hang at 0%. |
| `action.iconcache` | Rebuild the icon cache | Deletes the icon and thumbnail cache databases and restarts Explorer. Fixes blank or wrong icons on the desktop. |
| `action.flushdns` | Flush the DNS cache | Clears cached name lookups. Fixes a site that resolves to a stale address. |
| `action.resetnetwork` | Reset the network stack | Resets Winsock and the TCP/IP stack to their defaults. A last resort for a machine that will not connect. Requires a restart, and clears any manual proxy or static IP configuration. |
| `action.sfc` | Check system files (SFC) | Runs sfc /scannow to verify and repair protected system files. Takes several minutes. |
| `action.dism` | Repair the component store (DISM) | Runs DISM /RestoreHealth to repair the component store that SFC repairs from. Run this first if SFC cannot fix a file. Needs an internet connection and takes a while. |
| `action.optimizedrives` | Optimize drives (TRIM / defrag) | Sends TRIM to SSDs and defragments hard disks, choosing the right operation per drive. |
| `action.eventlogs` | Clear all event logs | Wipes every Windows event log. This destroys the crash and error history you would need to diagnose a problem later, so only do it when you are deliberately clearing traces of a fixed issue. |

## Presets

| Key | Tweaks | Description |
| --- | --- | --- |
| `debloat` | 14 | Removes the pre-installed Store apps most people never open. This cannot be undone by SigmaTweaks - anything you want back has to be reinstalled from the Microsoft Store. |
| `gaming` | 21 | Latency and frame-time work: scheduler priorities, capture off, mouse acceleration off, Nagle off, and a power plan that stops parking cores. Expect higher idle power draw. |
| `laptop` | 30 | Recommended, minus everything that costs battery life. Power throttling, core parking and USB suspend are all left alone on purpose. |
| `performance` | 31 | Everything in Recommended plus the settings that trade features or power draw for responsiveness. Includes SSD-only tweaks, which are skipped automatically on a hard disk. |
| `privacy` | 20 | Every telemetry, tracking, advertising and cloud-personalisation setting SigmaTweaks knows about. Nothing here weakens Defender, SmartScreen, UAC or the firewall. |
| `recommended` | 36 | The safe default. Reversible settings only - no apps are removed and no service you are likely to need is disabled. A good first run on any Windows 11 machine. |

