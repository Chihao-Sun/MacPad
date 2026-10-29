# Set up an iPad as your Mac display

**English** | [简体中文](首次配置.md)

Keep a physical monitor attached for the first setup. MacPad's monitor-free use starts after macOS login. Enter the FileVault startup password on a keyboard connected to the Mac.

## Prepare and install

1. Have an Apple Silicon Mac, a Sidecar-compatible iPad, a Mac keyboard and mouse, a physical monitor, and a USB-C data cable. A charge-only cable cannot carry wired Sidecar.
2. Check [Apple's Sidecar requirements](https://support.apple.com/en-ie/102597), including the same Apple Account and two-factor authentication. For wireless use, enable Wi-Fi, Bluetooth, and Handoff and keep the devices nearby. The Mac should not share its Internet connection, and the iPad should not share cellular data. Apple suggests checking the same Wi-Fi network when troubleshooting wireless use.
3. Download the DMG from [Releases](https://github.com/Chihao-Sun/MacPad/releases/latest), open it, and drag MacPad.app into Applications. Keep one installed copy and launch from that permanent location.
4. This package is ad-hoc signed and not notarized. If macOS blocks it, review its source and checksum and follow [Apple's app-opening instructions](https://support.apple.com/en-au/102445) in Privacy & Security. Do not disable system-wide protections.
5. Unlock the iPad and connect the data cable directly to the Mac. Accept the device trust or accessory prompt when requested. Finder sync and backups are unnecessary.
6. Open MacPad from the menu bar, choose the iPad, and select Connect. Confirm the picture, keyboard, and mouse. The iPad and virtual display should share one mirrored desktop.
7. Choose Display size. Native pixels come from the system, and presets follow the panel's aspect ratio. For a custom desktop, choose Custom and enter a width; Keep iPad aspect ratio calculates the height by default. You can turn it off to enter both dimensions. Pixel coverage and framebuffer limits are checked; settings are saved after the real mode and mirror relationship are confirmed.

MacPad does not require Remote Management, Remote Login, or Remote Apple Events. Leave FileVault and macOS automatic-login settings as they are.

## Enable daily automatic use

In Automatic connection, choose the settings you want:

| Option | Behaviour |
| --- | --- |
| Connect when no physical monitor is present | Try the iPad after login or after a monitor is unplugged, using a finite retry budget. |
| Switch wired/wireless automatically | Prefer a connected data cable and try wireless when it is absent. |
| Launch after Mac login | Run MacPad in the menu bar once the user has entered macOS. |

A fresh installation does not enable its login item without your choice. If macOS asks for approval, check MacPad under System Settings → General → Login Items. Close the settings window to keep running in the background.

## Verify each scenario

1. Keep the unlocked iPad connected by cable and unplug only the monitor's video cable. Check the picture, keyboard, and mouse. Reconnect the monitor if recovery is needed.
2. With wireless conditions ready, unplug the iPad data cable without selecting Disconnect. Check recovery, then reinsert it and check wired continuation. The picture can go black briefly. If wireless fails, unlock the iPad and reconnect its data cable.
3. Save your work and shut down normally. Remove power only after shutdown. Reconnect power and start the Mac, keeping the iPad attached and unlocked. Enter the startup password on a Mac-connected keyboard, then check automatic connection after login. Keep a recovery monitor nearby for the first test.

These checks cover different behaviours. One successful manual connection does not establish all three. Completely offline use still needs a separate test.

## Switch, pause and recover

- To move from wired to wireless, unplug the data cable while wireless conditions remain available.
- To return to wired, reinsert the USB-C data cable.
- A manual connection-method choice lasts for this session. Selecting Automatic, a cable-state change, or a new login restores the default preference.
- Disconnect pauses automatic connection. Select Connect to resume.

An unfinished native request keeps its token after a local timeout, so MacPad does not start a duplicate. After three attempts without a stable desktop, automatic calls pause until the device reappears, a cable changes, the Mac wakes, or you retry manually. A normal refresh or timer tick does not restart an unlimited retry loop. The system may still show an individual connection-failure dialog.

## Update or uninstall

Attach a spare monitor before updating or quitting when the iPad is your only display. Quitting removes the virtual display owned by MacPad.

Before uninstalling, turn off login launch in MacPad, quit, and remove the app. Local diagnostics can be removed separately; see [privacy notes](PRIVACY.md).
