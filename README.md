# termux-local-adb

Keep local ADB alive in Termux across Wi-Fi and cellular transitions.

This project bootstraps Android's dynamic Wireless Debugging endpoint from Termux, switches `adbd` to legacy TCP mode on port `5555`, and reconnects through `127.0.0.1:5555`. On the tested Samsung device, the localhost ADB connection remained available after Wi-Fi was turned off and the phone moved to cellular data.

## How it works

1. Android Wireless Debugging provides a temporary dynamic ADB endpoint after boot.
2. `restore-local-adb.sh` discovers and verifies that endpoint.
3. It runs `adb tcpip 5555` through the verified connection.
4. Termux reconnects to `127.0.0.1:5555`.
5. Stale dynamic transports are removed.
6. Optional phantom-process mitigation settings are reapplied.

The script first checks whether `127.0.0.1:5555` is already alive, so normal recovery is fast. Dynamic port probing is only used for bootstrap/recovery.

## Requirements

- Android device with Wireless Debugging support
- Termux
- `android-tools`
- `python`
- Termux:Boot for automatic recovery after reboot
- Tasker is optional, but the included project can enable Wireless Debugging during boot on devices where Android does not restore it automatically
- Termux:Tasker is only needed if you use the included `Restore adb` Tasker task

Install the Termux dependencies:

```sh
pkg install android-tools python
```

## Install

Clone the repository, then install the scripts:

```sh
git clone https://github.com/sionie/termux-local-adb.git
cd termux-local-adb
mkdir -p ~/bin ~/.termux/boot
cp restore-local-adb.sh ~/bin/restore-local-adb.sh
cp boot/adb-autostart.sh ~/.termux/boot/adb-autostart.sh
chmod 700 ~/bin/restore-local-adb.sh ~/.termux/boot/adb-autostart.sh
```

If you use the included Tasker `Restore adb` task with Termux:Tasker, place a real wrapper or copy in `~/.termux/tasker/`; do not rely on a symlink that resolves outside that directory unless `allow-external-apps=true` is configured.

## Discovery hosts

By default the public script probes `127.0.0.1` only. You can add fallback hosts without editing the script:

```sh
ADB_DISCOVERY_HOSTS="127.0.0.1 100.x.y.z" ~/bin/restore-local-adb.sh
```

This can be useful for a private VPN/Tailscale address when loopback discovery alone is insufficient. Do not commit personal IP addresses to the repository.

## Tasker project

`tasker/Boot.prj.xml` is the tested Tasker export. Its `On Boot` task waits for Android to settle, launches Termux, and sets the global `adb_wifi_enabled` value twice. The separate `Restore adb` task enables Wireless Debugging and invokes the Termux:Tasker restore action.

Whether the Tasker bootstrap is necessary depends on the device/ROM. Once `127.0.0.1:5555` has been established, the tested device kept local ADB alive when Wi-Fi was disabled.

## Security warning

**`adb tcpip 5555` is not a loopback-only setting.** Although this project reconnects from Termux through `127.0.0.1:5555`, Android's legacy ADB TCP listener may also be reachable through other active network interfaces. Do not assume that using `127.0.0.1` as the client address prevents port 5555 from being exposed on Wi-Fi, cellular/VPN, USB networking, or other interfaces.

Use this only on a device and networks you control. Keep Android ADB authentication enabled, review debugging authorizations, and verify actual listener/reachability on your ROM before relying on this setup. Do not intentionally expose ADB port 5555 to an untrusted LAN, VPN peer, or the public Internet.

Never commit SSH private keys, API tokens, session cookies, pairing codes, personal IP addresses, or other credentials. Runtime logs and caches are excluded by `.gitignore`.

## Tested behavior

Validated on a Samsung Galaxy device running Android 16 / One UI:

- reboot -> dynamic Wireless ADB discovery
- dynamic endpoint -> `adb tcpip 5555`
- reconnect -> `127.0.0.1:5555 device`
- Wi-Fi off / cellular active -> localhost ADB remained connected

Behavior may differ across Android versions and vendor ROMs.
