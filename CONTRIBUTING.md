# Contributing

**English** | [简体中文](CONTRIBUTING.zh-CN.md)

Contributions use GPL-3.0-only. Check that you have the right to submit your changes under that license.

## Report a problem

Include the MacPad version, Mac and iPad models, both OS versions, connection method, reproduction steps, and time of failure. Say whether the Mac had reached its desktop, whether a physical monitor was attached, whether Disconnect had been selected, and whether manual connection recovered the picture.

Review logs and screenshots for personal device names and paths. Do not submit passwords, certificates, tokens, or unreviewed personal diagnostics.

## Change and verify

Run `zsh scripts/test.sh` on an Apple Silicon Mac. Build with `zsh scripts/build.sh`, which increments internal BUILD. Compilation and policy tests are separate from physical-device and cold-start acceptance.

Connection changes must cover wired preference, wireless recovery, manual overrides, deliberate disconnect/pause, failure budgets, pending native requests, and stale callbacks. A local timeout does not cancel Apple's request. Check the real display mode and mirror relationship; the mere existence of a virtual display does not establish a connected iPad.

Panel adaptation needs tests for native pixels, portrait and landscape ratios, preference migration, and framebuffer limits. A native-flagged mode is different from an extra mirrored desktop mode. Do not call the largest listed mode the panel's native pixels. Distinguish geometry fixtures from real-device tests, and picture latency from unplug recovery time.

Keep a spare monitor available before terminating the user's only display owner. Do not force power loss for a test. Preserve passwords, FileVault, and system network settings.

Describe the concrete problem, resulting behaviour, tested devices, and remaining gaps. Include only code and assets you have permission to distribute, and retain required copyright and license notices.
