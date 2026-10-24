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

The script first checks whether `127.0.0.1:5555` is already alive, so normal recovery is fast. Dynamic port probing is only used for bootstrap/recovery. If `zeroconf` is installed, the script first looks for the `_adb-tls-connect._tcp.local.` DNS-SD service advertised by Wireless Debugging. If no service is found, it tries `nmap` (if installed), then the original Python scanner.

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
pkg install git android-tools python
# Optional fallback scanner (device performance varies):
pkg install nmap
# Optional DNS-SD discovery, preferred when Wireless Debugging advertises a service:
python -m pip install zeroconf
```

## First-time ADB pairing (required after Termux reset)

**A new Termux installation or cleared Termux app data creates a new ADB authentication key.** Before expecting automatic recovery, pair Termux with Android Wireless Debugging **once**. Turning on Wireless Debugging alone is not sufficient. Pairing should normally survive reboots as long as the Termux ADB keys and Android's paired-device authorization are retained.

1. On the Android device, enable **Developer options → Wireless debugging**. In **Pair device with pairing code**, note the shown IP:pairing-port and the temporary pairing code.
2. In **Termux on the same device**, run `adb pair DEVICE_IP:PAIRING_PORT` and enter the displayed code when prompted. Or supply the code as the second argument for a non-interactive invocation; avoid writing it to logs or scripts.
3. Verify the command reports `Successfully paired`. The **pairing port** is temporary and is **not** the separate **IP address & port** shown on the main Wireless Debugging screen.
4. With Wireless Debugging still enabled, run `~/bin/restore-local-adb.sh`. It discovers the current TLS connect endpoint, authenticates using the paired key, and promotes it to `127.0.0.1:5555`. Confirm with `adb devices`.
5. On later reboots, Tasker can enable Wireless Debugging while Termux:Boot invokes the recovery script; normal reboots do **not** require re-pairing. Repeat pairing if the Termux ADB keys or Android paired-device entry are lost.

Do not paste pairing codes or private keys into issues or commit them. Keep Android's ADB authorization enabled.

## Install

Clone the repository, then install the scripts:

```sh
git clone https://github.com/sionie/termux-local-adb.git
cd termux-local-adb
mkdir -p ~/bin ~/.termux/boot
cp restore-local-adb.sh ~/bin/restore-local-adb.sh
cp boot/adb-autostart.sh ~/.termux/boot/20-adb-autostart
chmod 700 ~/bin/restore-local-adb.sh ~/.termux/boot/20-adb-autostart
```

**Open the Termux:Boot app at least once after installation.** Android will not necessarily deliver boot events to an app that has never been launched. Ensure that battery/background restrictions do not prevent Termux:Boot or Tasker from running. To also start SSH after reboot, install `openssh` and create an executable `~/.termux/boot/00-sshd` containing a shebang and `sshd`. SSH is independent of the local ADB restore.

If you use the included Tasker `Restore adb` task with Termux:Tasker, place a real wrapper or copy in `~/.termux/tasker/`; do not rely on a symlink that resolves outside that directory unless `allow-external-apps=true` is configured.

## Discovery behavior

The default discovery range is TCP 30000-49999, with a 35-second per-host probe budget. On resource-constrained Android tablets, the old Python-only probe can fail to reach the live port before its deadline. `nmap` provides an alternative connect scan, but on the tested Tab Active 3 its full-range scan could still exceed one minute. DNS-SD is preferred when available. A successful existing `127.0.0.1:5555` connection still bypasses all discovery. **A full cold-boot recovery must be verified on each target device**; success after a previously established ADB connection does not prove discovery works on reboot.

## Discovery hosts

By default the public script probes `127.0.0.1` only. You can add fallback hosts without editing the script:

```sh
ADB_DISCOVERY_HOSTS="127.0.0.1 100.x.y.z" ~/bin/restore-local-adb.sh
```

This can be useful for a private VPN/Tailscale address when loopback discovery alone is insufficient. Do not commit personal IP addresses to the repository.

## Tasker project

Import `tasker/Boot.prj.xml` as a **Tasker project** (in Tasker, long-press a project tab, then Import Project). The included tasks retain the names **On Boot** and **Restore adb**. Do not enable duplicate On Boot profiles from older imported projects.

The `On Boot` profile responds to Android boot, waits **30 seconds** (check that Tasker displays *30 Seconds*, not hours), launches Termux, then waits five more seconds. It issues the Custom Setting write `adb_wifi_enabled = 1` up to **12 times** with **5-second waits** between attempts, to tolerate a slow boot. This version deliberately uses repeated simple actions rather than a Tasker loop whose imported XML had failed on the test device. It does **not** inspect the state between writes or stop early. No Tailscale action is included.

The `Restore adb` task is optional and contains a Termux:Tasker action. If you want to use that task, install Termux:Tasker, configure its Android permissions and Termux external-app access as required, and ensure the referenced `restore-local-adb.sh` is actually available from the Termux:Tasker scripts directory. The **Termux:Boot script works without Termux:Tasker**.

On some Android ROMs, changing the `adb_wifi_enabled` global setting needs additional Tasker permission, such as WRITE_SECURE_SETTINGS granted by a trusted ADB session. A profile being enabled does not prove the setting was applied: after a reboot, check that Wireless Debugging really turns on and inspect Tasker Run Log if not.

**Verified on Galaxy Tab Active 3 (SM-T575N, Android 13), 2026-10-24:** after initial pairing, the imported fixed `On Boot` Tasker workflow enabled Wireless Debugging, Termux:Boot launched the recovery script, and the script discovered a changing TLS port without a manually entered port. It produced `127.0.0.1:5555 device` after reboot. This is one real-device validation, not a guarantee for every Android build.

### Troubleshooting

- `adb devices` empty while Wireless Debugging is on: **first confirm pairing**. Try `adb pair IP:PAIRING_PORT` with a fresh code if Termux was reset.
- Log says `ERROR no verified ADB endpoint`: distinguish Wireless Debugging being off, unpaired keys, and port discovery failure. The pairing port is different from the connection port.
- SSH port 8022 unavailable after reboot: configure Termux:Boot to run `sshd`; Tasker does not automatically start SSH.
- After changing Tasker XML: re-import as a project and disable the old boot profile so two profiles do not race.

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
