# Privacy and local diagnostics

**English** | [简体中文](隐私说明.md)

MacPad V1.3.1 reads system-provided device and display state. Local preferences store the device selection, native panel dimensions, desktop size, and automatic-connection options. Display choices are associated with device names. Hardware serial numbers and hardware UUIDs are not collected.

`~/Library/Application Support/MacPad/status.json` and `latest-session.log` are written when state changes. They can contain device/display names, an installation path, process IDs, connection methods, times, display modes, and errors. They stay on the Mac and are not automatically sent to maintainers.

The current app has no project-operated server, advertising analytics, automatic diagnostic upload, or automatic update service. It does not store login passwords, back up the iPad, or record the picture to video files. Apple manages Sidecar transport and Apple Account services; this statement does not mean Apple's system services never use a network.

Login launch is an explicit user setting. MacPad does not alter FileVault, macOS automatic login, Remote Management, VPN, proxy, DNS, or routing settings.

Review logs and screenshots before sharing them. Remove personal device names, local paths, and private desktop content. Do not upload credentials, tokens, certificates, device identifiers, or an unreviewed diagnostic directory.

For uninstalling, attach a spare monitor, disable login launch in MacPad, quit, and remove the app. You can also remove the diagnostic directory above. Removing app files does not erase every history record retained by macOS.
