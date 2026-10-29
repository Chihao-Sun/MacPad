<p align="center">
  <img src="Resources/MacPadIcon.png" width="112" alt="MacPad icon">
</p>

# MacPad

**English** | [简体中文](README.zh-CN.md)

[Download](https://github.com/Chihao-Sun/MacPad/releases/latest) · [Setup guide](docs/GETTING_STARTED.md) · [Report a problem](https://github.com/Chihao-Sun/MacPad/issues)

Turn your iPad into a portable display for your Mac mini. MacPad is free and open source. Install it on the Mac; the iPad needs no extra app.

Apple Sidecar carries the picture. MacPad keeps a virtual display alive, manages a mirrored desktop, and offers HiDPI sizes suited to the iPad's screen. With compatible devices and accounts, you can use an existing USB-C data cable or connect wirelessly, without buying a capture card or display dummy.

Once you have configured and tested it, MacPad can run from the menu bar after login and connect automatically. Closing its settings window keeps the desktop running.

## What MacPad makes easier

- Keep using the iPad after unplugging the physical monitor. The virtual display retains the Mac desktop after login.
- Keep the iPad and virtual display on one mirrored desktop, so the pointer and windows cannot disappear into an invisible extension between them.
- Start from the menu bar after login and connect automatically when no physical monitor is attached.
- Prefer USB-C when a data cable is present, try wireless after unplugging it, and return to wired when it is reinserted. A temporary manual connection choice is also available.
- Read the iPad's native pixels and aspect ratio to generate HiDPI choices. Choose larger text or more workspace, enter a custom size, and remember the choice for that device.
- Keep at most one native connection request pending, even after a local timeout. After three unsuccessful attempts in one device-state cycle, wait for a real device change or a manual retry instead of repeatedly triggering system error dialogs. The system may still show an individual connection error.
- Pause automatic connection with Disconnect and resume it with Connect. Settings can be closed while MacPad stays in the menu bar, without a persistent Dock icon.
- Save a display size only after verifying the actual mode and mirror relationship. A failed change preserves the previous desktop.

## Download and first setup

Download the Apple Silicon DMG from [GitHub Releases](https://github.com/Chihao-Sun/MacPad/releases/latest). Open it, drag MacPad.app into Applications, and launch that installed copy.

The current package is **ad-hoc signed and not Apple notarized**. macOS may block the first launch. After checking the download source and checksum, follow [Apple's instructions](https://support.apple.com/en-au/102445) for reviewing the app in System Settings → Privacy & Security. Do not disable system-wide security protections.

1. Keep a physical monitor attached for setup, with a keyboard and mouse that can operate the Mac. Check the compatibility section below.
2. Confirm that both devices meet [Apple's Sidecar requirements](https://support.apple.com/en-ie/102597). Sign in to the same Apple Account with two-factor authentication. For wireless use, enable Wi-Fi, Bluetooth, and Handoff, and keep the devices nearby.
3. Install MacPad in a permanent Applications directory and keep one working copy. Set up login launch from that location, not from a mounted DMG or temporary extraction folder.
4. Make the first connection with a USB-C data cable. Unlock the iPad and trust the Mac if prompted. Finder sync and backups are unnecessary.
5. Open MacPad from the menu bar, choose your iPad, and select Connect. Check the picture, keyboard, and mouse before choosing a Display size.
6. In Automatic connection, enable the options you want: connect when no physical monitor is present, switch wired/wireless automatically, and launch after Mac login. A fresh installation does not register its login item without your choice.
7. Keep the iPad cable attached and unplug only the physical monitor's video cable. Check the desktop, then separately test wireless recovery by unplugging the iPad cable and wired recovery by plugging it back in.
8. Before travel, save your work and shut down normally. Disconnect power only after shutdown. Reconnect power and start the Mac, keeping the iPad connected and unlocked. Enter the startup password on a keyboard connected to the Mac, then check automatic connection after login. Keep a recovery monitor nearby for the first test.

For daily switching, unplug the data cable to try wireless and reinsert it to return to wired. Disconnect means pause, so it is not the switching control. A manual transport choice lasts for the current session; the next cable-state change or login restores automatic wired preference.

See the [setup and recovery guide](docs/GETTING_STARTED.md). If the iPad is your only display, attach a spare monitor before updating or quitting. Quitting removes the virtual display owned by the process.

## How display sizes work

MacPad reads the Sidecar display's native pixel dimensions, then generates desktop sizes with the same aspect ratio. It does not apply one 11-inch preset list to every iPad. If detection fails, the interface labels the compatibility fallback instead of presenting it as a detected panel.

On the tested 11-inch iPad Pro, the default desktop is 1344 × 938, rendered at 2688 × 1876 and scaled to a 2388 × 1668 panel. Other panels get sizes calculated from their reported pixels. These examples belong to the tested panel:

| Desktop size | Rendered pixels |
| --- | --- |
| 1194 × 834 | 2388 × 1668 |
| 1280 × 894 | 2560 × 1788 |
| 1344 × 938 (default) | 2688 × 1876 |
| 1600 × 1118 | 3200 × 2236 |
| 2388 × 1668 | 4776 × 3336 |

Use Display size or Custom to choose a desktop. Keep iPad aspect ratio is on by default. Custom dimensions must cover the panel pixels and fit within the framebuffer limits. Larger rendered desktops cost more graphics and encoding work; Sidecar controls the final frame rate and transmission quality. HiDPI does not imply a one-to-one panel mapping at every size.

## Latency and switching

| Measurement | Evidence so far |
| --- | --- |
| USB-C picture latency | End-to-end latency has not been measured; no millisecond figure is published. |
| Wireless picture latency | End-to-end latency has not been measured; no millisecond figure is published. |
| Recovery after unplugging a data cable | In an earlier device test, the user observed about 5 seconds; logs showed online status at about 5 seconds and stable verification at about 6 seconds. |

Picture latency measures an input-to-visible-response delay. Recovery time measures how long it takes for the picture to return after unplugging. Switching can briefly interrupt the picture; there is no zero-interruption or fixed-time guarantee.

## Compatibility and limits

V1.3.1 provides an arm64 build with a macOS 14 minimum compilation target. Physical testing covers one M4 Mac mini on macOS 26.6.2 and one second-generation 11-inch iPad Pro. The iPadOS version has not been recorded. No Intel build is supplied, and other OS versions still need testing.

Different native dimensions and portrait/landscape ratios have policy tests. That is not physical acceptance of other iPad models. MacPad depends on internal system interfaces, which can change with macOS updates. Both devices must still qualify for Apple Sidecar.

MacPad works after login. It does not display the FileVault startup unlock screen, save your password, or enable automatic macOS login. Fully offline operation, real sleep/wake, and forcing wireless while the cable stays attached have not been separately verified. It does not provide remote desktop across the public Internet or full macOS finger-touch input.

## Build from source

On an Apple Silicon Mac, install Xcode or command-line developer tools with the required macOS SDK, and have Python 3 available:

```sh
zsh scripts/test.sh
zsh scripts/build.sh
```

The app is generated in `.build/Release.noindex/<VERSION>/MacPad.app`. The build script increments internal BUILD and applies an ad-hoc signature. It does not automatically install, replace, or launch the app.

Compilation and policy tests do not establish notarization, physical-device acceptance, or a successful cold boot. Keep a physical monitor attached for the first use of a self-built app.

## License, privacy and contributions

MacPad is free under [GPL-3.0-only](LICENSE), including its supplied project artwork. Commercial use is permitted; distributing modified versions requires compliance with the GPL and corresponding source obligations. Apple's system components are governed by their own terms and are not distributed here.

Diagnostics stay on your Mac and are not uploaded automatically. Review logs and screenshots before sharing them and remove personal device names, local paths, and private content. Read the [privacy notes](docs/PRIVACY.md) and [contribution guide](CONTRIBUTING.md).
