# MacPad V1.4.0

**English** | [简体中文](版本状态.md)

[Download V1.3.2](https://github.com/Chihao-Sun/MacPad/releases/tag/V1.3.2) · [Setup guide](GETTING_STARTED.md) · [Home](../README.md)


V1.4.0 / build 46 adds a global connect shortcut (default ⌃⌥⌘L), editable in Automatic connection, with inline registration/system-conflict feedback. Manual disconnect now remains paused across USB changes, system wake and MacPad restart. Diagnostics also provide independent per-process status during upgrades. Sidebar row/icon spacing follows the supplied macOS System Settings reference.

The current source is V1.4.0; the downloadable release remains V1.3.2. Policy, shortcut-registration and build checks passed. Live shortcut reconnect and custom recording were verified on the development Mac. Physical sleep/wake, cable reinsertion while paused and new-device installation are not claimed as completed tests.

## Previous baseline

V1.3.2 / build 35 updates the app icon to v0.14.1 and menu bar to v0.5.6 (40×23 pt, #7163FF), with the approved Dock hero. Transport and HiDPI policies are unchanged.

Previous application baseline: V1.3.1, build 32. The application and installer are unchanged by the documentation update on 30 October 2026. The release source is commit [`7f7245a`](https://github.com/Chihao-Sun/MacPad/commit/7f7245ae1ce4c039bfe1e915d8127cbad00a0b6f).

## What this version does

- Uses Apple's built-in Sidecar, with installation and setup on the Mac. The iPad needs no extra app.
- Keeps its own virtual display alive, so the iPad can be the only display after macOS login. No separate BetterDisplay installation, capture card or display dummy is needed.
- Keeps the iPad and virtual display in one mirrored desktop. Desktop sizes follow the iPad's reported native pixels and aspect ratio, with HiDPI presets, custom sizes and saved choices per device.
- Prefers USB-C when macOS recognizes a data connection. Unplugging tries wireless recovery; reinserting the cable tries wired again. A manual choice lasts until the next cable change or login.
- Runs in the menu bar and can start at login. Closing the settings window keeps the desktop running. Disconnect pauses automatic connection; Connect resumes it.
- Keeps native connection requests single-flight and limits repeated attempts. Diagnostics stay local. Official releases will always be free under GPL-3.0-only.

## Latest device check

On 30 October 2026, automatic mode was showing wireless while the Mac had no USB iPad in its device list. After cable reinsertion, the system recognized the iPad and MacPad's existing logic switched to wired. The user confirmed success; system status also showed wired configuration and an intact HiDPI mirror. No program change was needed for this check.

| Check | Observation on the tested setup |
| --- | --- |
| Cable reinsertion | About 6 seconds to the app's stable wired verification. |
| Wireless recovery in the same session | About 8 seconds to stable verification. An earlier test recovered in about 5 seconds. |
| Connected state | Automatic mode, USB iPad detected, wired configuration, mirrored desktop. |

These are individual recovery observations, not input-to-picture latency measurements or timing guarantees. Physical coverage remains one M4 Mac mini and one second-generation 11-inch iPad Pro. Other panel dimensions have policy tests, not device acceptance.

## Before relying on it away from a monitor

Follow the [important setup and restart operations](GETTING_STARTED.md). Supply a keyboard and a mouse or trackpad connected to the Mac mini. Keep login launch and the required automatic connection options enabled, rehearse password entry with a monitor, and unlock the iPad. MacPad starts after login and cannot handle the FileVault startup unlock screen.

The download is ad-hoc signed and not Apple notarized. Installation on another Mac, a cold boot of this exact build, fully offline use and real sleep/wake still need separate checks. macOS updates can affect the internal system interfaces MacPad uses.