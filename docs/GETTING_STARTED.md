# Important operations

**English** | [简体中文](首次配置.md)

> [!IMPORTANT]
> MacPad starts **after macOS login**. It cannot show the FileVault startup screen or enter your password. For monitor-free restart, configure automatic connection and login launch, then rehearse startup with a physical monitor. Missing these steps can leave the iPad without a Mac picture after reboot.

### Start with AI assistance (recommended)

Copy the prompt for the AI you use. An agent with local tools can handle Mac-side installation and settings; a chat-only assistant can guide you through them. Follow its instructions when a system confirmation, iPad unlock or password requires your action. **AI cannot bypass Sidecar compatibility or Mac login.**

All four templates share the same setup goals and safety boundaries. You still need your own keyboard and a mouse or trackpad connected to Mac mini.

<a id="ai-codex"></a>

<details open>
<summary>Codex · copy prompt</summary>

```text
Act as my local setup assistant. Check your terminal and computer-control tools, perform the task within existing permissions, and stop at a clear step when my action is needed.

Goal: configure free, open-source MacPad on this Mac so the iPad becomes Mac mini's mirrored display after login, with panel-aware HiDPI, login launch, automatic connection without a physical monitor, and wired/wireless continuation.
Repository: https://github.com/Chihao-Sun/MacPad
Setup: https://github.com/Chihao-Sun/MacPad/blob/main/docs/GETTING_STARTED.md
Read the current README, setup guide and latest Release first. Check chip, OS, Sidecar compatibility, installed version and available tools. Ask only for missing essentials; do not collect passwords, Apple Account addresses or serial numbers. I will confirm the same account and two-factor authentication.
You may make reversible changes limited to MacPad: verify the public download and checksum, install one permanent app copy, select my iPad, and configure automatic connection, login launch, transport switching and HiDPI mirroring. Prefer app settings; inspect source instead of guessing preference keys.
I will supply a keyboard and a mouse or trackpad connected to Mac mini. First use can be wireless; USB requires a data-capable USB-C cable, not Thunderbolt. Keep a physical monitor for initial setup. If the iPad is the only display, do not quit or replace the display owner.
Do not disable FileVault, remove the password, enable macOS automatic login, disable global security, enable SSH/remote management/remote scripting, or sync/back up the iPad. Do not add BetterDisplay, an iPad app or purchased hardware. The package is not Apple notarized; I will handle trust/security prompts, iPad unlock and passwords.
Give me one clear set of steps whenever I need to act. Verify picture/input, monitor-free mirroring, cable transitions, and actual post-reboot connection separately. Rehearse password entry with a visible monitor first; MacPad cannot handle FileVault startup unlock.
Finish with separate lists of configured settings, physically confirmed results and untested items. A successful command or running process is not proof of a picture on iPad. If local tools are unavailable, guide me instead of claiming actions.
```

</details>

<a id="ai-claude-code"></a>

<details>
<summary>Claude Code · copy prompt</summary>

```text
Configure the app as a local task. Use UI tools if available; with terminal access only, inspect source and local state while I handle UI confirmations. Do not assume computer-control tools exist.

Goal: configure free, open-source MacPad on this Mac so the iPad becomes Mac mini's mirrored display after login, with panel-aware HiDPI, login launch, automatic connection without a physical monitor, and wired/wireless continuation.
Repository: https://github.com/Chihao-Sun/MacPad
Setup: https://github.com/Chihao-Sun/MacPad/blob/main/docs/GETTING_STARTED.md
Read the current README, setup guide and latest Release first. Check chip, OS, Sidecar compatibility, installed version and available tools. Ask only for missing essentials; do not collect passwords, Apple Account addresses or serial numbers. I will confirm the same account and two-factor authentication.
You may make reversible changes limited to MacPad: verify the public download and checksum, install one permanent app copy, select my iPad, and configure automatic connection, login launch, transport switching and HiDPI mirroring. Prefer app settings; inspect source instead of guessing preference keys.
I will supply a keyboard and a mouse or trackpad connected to Mac mini. First use can be wireless; USB requires a data-capable USB-C cable, not Thunderbolt. Keep a physical monitor for initial setup. If the iPad is the only display, do not quit or replace the display owner.
Do not disable FileVault, remove the password, enable macOS automatic login, disable global security, enable SSH/remote management/remote scripting, or sync/back up the iPad. Do not add BetterDisplay, an iPad app or purchased hardware. The package is not Apple notarized; I will handle trust/security prompts, iPad unlock and passwords.
Give me one clear set of steps whenever I need to act. Verify picture/input, monitor-free mirroring, cable transitions, and actual post-reboot connection separately. Rehearse password entry with a visible monitor first; MacPad cannot handle FileVault startup unlock.
Finish with separate lists of configured settings, physically confirmed results and untested items. A successful command or running process is not proof of a picture on iPad. If local tools are unavailable, guide me instead of claiming actions.
```

</details>

<a id="ai-cursor"></a>

<details>
<summary>Cursor · copy prompt</summary>

```text
Handle this setup in a mode that can execute tasks. Check terminal and local UI tools, perform reversible steps you can execute, and give exact setting paths for the rest. No MacPad product-code changes are needed.

Goal: configure free, open-source MacPad on this Mac so the iPad becomes Mac mini's mirrored display after login, with panel-aware HiDPI, login launch, automatic connection without a physical monitor, and wired/wireless continuation.
Repository: https://github.com/Chihao-Sun/MacPad
Setup: https://github.com/Chihao-Sun/MacPad/blob/main/docs/GETTING_STARTED.md
Read the current README, setup guide and latest Release first. Check chip, OS, Sidecar compatibility, installed version and available tools. Ask only for missing essentials; do not collect passwords, Apple Account addresses or serial numbers. I will confirm the same account and two-factor authentication.
You may make reversible changes limited to MacPad: verify the public download and checksum, install one permanent app copy, select my iPad, and configure automatic connection, login launch, transport switching and HiDPI mirroring. Prefer app settings; inspect source instead of guessing preference keys.
I will supply a keyboard and a mouse or trackpad connected to Mac mini. First use can be wireless; USB requires a data-capable USB-C cable, not Thunderbolt. Keep a physical monitor for initial setup. If the iPad is the only display, do not quit or replace the display owner.
Do not disable FileVault, remove the password, enable macOS automatic login, disable global security, enable SSH/remote management/remote scripting, or sync/back up the iPad. Do not add BetterDisplay, an iPad app or purchased hardware. The package is not Apple notarized; I will handle trust/security prompts, iPad unlock and passwords.
Give me one clear set of steps whenever I need to act. Verify picture/input, monitor-free mirroring, cable transitions, and actual post-reboot connection separately. Rehearse password entry with a visible monitor first; MacPad cannot handle FileVault startup unlock.
Finish with separate lists of configured settings, physically confirmed results and untested items. A successful command or running process is not proof of a picture on iPad. If local tools are unavailable, guide me instead of claiming actions.
```

</details>

<a id="ai-chat-assistant"></a>

<details>
<summary>ChatGPT / Claude / Gemini / DeepSeek · copy prompt</summary>

```text
Guide me through this setup. First establish whether you can access my Mac. If not, say so and give one manageable set of steps at a time, waiting for my result. Do not pretend to click or execute commands.

Goal: configure free, open-source MacPad on this Mac so the iPad becomes Mac mini's mirrored display after login, with panel-aware HiDPI, login launch, automatic connection without a physical monitor, and wired/wireless continuation.
Repository: https://github.com/Chihao-Sun/MacPad
Setup: https://github.com/Chihao-Sun/MacPad/blob/main/docs/GETTING_STARTED.md
Read the current README, setup guide and latest Release first. Check chip, OS, Sidecar compatibility, installed version and available tools. Ask only for missing essentials; do not collect passwords, Apple Account addresses or serial numbers. I will confirm the same account and two-factor authentication.
You may make reversible changes limited to MacPad: verify the public download and checksum, install one permanent app copy, select my iPad, and configure automatic connection, login launch, transport switching and HiDPI mirroring. Prefer app settings; inspect source instead of guessing preference keys.
I will supply a keyboard and a mouse or trackpad connected to Mac mini. First use can be wireless; USB requires a data-capable USB-C cable, not Thunderbolt. Keep a physical monitor for initial setup. If the iPad is the only display, do not quit or replace the display owner.
Do not disable FileVault, remove the password, enable macOS automatic login, disable global security, enable SSH/remote management/remote scripting, or sync/back up the iPad. Do not add BetterDisplay, an iPad app or purchased hardware. The package is not Apple notarized; I will handle trust/security prompts, iPad unlock and passwords.
Give me one clear set of steps whenever I need to act. Verify picture/input, monitor-free mirroring, cable transitions, and actual post-reboot connection separately. Rehearse password entry with a visible monitor first; MacPad cannot handle FileVault startup unlock.
Finish with separate lists of configured settings, physically confirmed results and untested items. A successful command or running process is not proof of a picture on iPad. If local tools are unavailable, guide me instead of claiming actions.
```

</details>

### Manual first setup

1. Keep a physical monitor attached and have your own keyboard and a mouse or trackpad connected to the **Mac mini**, not only to the iPad. Check the [compatibility limits](../README.md#compatibility-and-limits).
2. Confirm [Apple's Sidecar requirements](https://support.apple.com/en-qa/102597): compatible devices, the same Apple Account, and two-factor authentication. For wireless, enable Wi-Fi, Bluetooth, and Handoff and keep the devices within 10 metres. Do not share the iPad's cellular or the Mac's Internet connection.
3. Download the Apple Silicon DMG from [Releases](https://github.com/Chihao-Sun/MacPad/releases/latest). Open it, drag MacPad.app into Applications, and launch that permanent copy. Keep one installed copy; do not set login launch from the mounted DMG.
4. The package is **ad-hoc signed and not Apple notarized**. If macOS blocks it, review the source and checksum, then follow [Apple's instructions](https://support.apple.com/en-au/102445) for that app in Privacy & Security. Do not disable system-wide protections.
5. **The first connection may be wireless.** Unlock the iPad and select Automatic in MacPad. A prior USB connection is not required. Alternatively, connect a data cable and trust the Mac when prompted. The original Apple USB-C cable supplied with a USB-C iPhone or iPad is normally suitable; a charge-only cable is not. No Thunderbolt cable is needed. Finder sync and backups are unnecessary.
6. Open MacPad from the menu bar, choose the iPad, and select Connect. Check the picture, keyboard, and mouse, then choose a Display size. Presets and Custom let you adjust text size and workspace.
7. For automatic use after login, enable **connect when no physical monitor is present** and **launch after Mac login**. Approve MacPad under System Settings → General → Login Items if macOS requests it. Enable automatic wired/wireless switching if you want both methods to follow cable changes.
8. Unplug only the physical monitor's video cable and check the iPad desktop. If you use both transports, test data-cable unplug/replug separately. Keep a recovery monitor nearby for the first restart test.

### Restart without a visible login screen

**Rehearse this with a physical monitor first.** A keyboard that works after login is not proof that it works at the FileVault screen. Pair the wireless keyboard with the Mac mini, charge it, and confirm it can type at startup. A keyboard attached only to the iPad cannot enter the Mac's startup password through Sidecar. Keep a tested wired connection or USB receiver available if your keyboard needs one.

1. Save work and shut down normally. Remove power only after shutdown. On arrival, connect Mac mini power and press its power button. Keep the iPad awake and unlocked, with the chosen wired or wireless conditions ready.
2. Turn on the Mac-connected keyboard and wait for the startup stage established during rehearsal. Check Caps Lock and the input layout you tested. Use a harmless modifier such as Shift to wake the keyboard if needed.
3. Follow the account/focus sequence you verified. If the default account's password field is already focused, type the password once and press Return. If rehearsal showed an account tile first, use the verified key sequence to open its password field before typing. Multiple accounts and OS updates can change this sequence; there is no universal blind-login key sequence.
4. After the correct password is accepted, macOS enters the user session. MacPad then launches, retains a virtual desktop, and searches for the iPad. Allow the system time to finish login and discovery.
5. If no picture appears, avoid repeatedly typing passwords blindly. Unlock the iPad and try its data cable; if necessary, reconnect the recovery monitor and inspect the actual login or connection state.

We recommend keeping a login password and FileVault enabled. MacPad does not save or type passwords and does not require macOS automatic login. Automatic login is a separate OS setting; FileVault restricts its availability. Removing local login protection makes a lost or stolen Mac easier to access.

### Daily use, recovery and updates

- Close the settings window to keep MacPad running in the menu bar. Quitting removes its virtual display.
- Unplug the data cable to try wireless; reinsert it to return to wired. Switching may briefly interrupt the picture. A temporary manual transport choice resets on the next cable change or login.
- If a cable is attached but Automatic still shows wireless, check that macOS has recognized the USB iPad. Charging alone does not establish a data connection. Unlock the iPad, reseat the cable and handle any accessory or trust prompt; try a cable known to carry data if it remains unrecognized. MacPad prefers wired once the USB connection is detected.
- Disconnect pauses automatic connection. Select Connect to resume. After repeated failures, unlock the iPad and reconnect its cable or retry manually; ordinary refresh does not restart an unlimited retry loop.
- Attach a spare monitor before updating or quitting when the iPad is your only display. Before uninstalling, disable login launch in MacPad, quit, and remove the app. Local diagnostics are described in [privacy notes](PRIVACY.md).

Rehearse cable changes and login separately; one successful manual connection does not prove monitor-free startup. Fully offline operation still needs a separate test.
