#!/data/data/com.termux/files/usr/bin/bash

# Termux:Boot entrypoint.
# Give Android/Tasker/Wireless Debugging time to initialize, then bootstrap
# persistent localhost ADB. Retries tolerate slower boots.

sleep "${ADB_BOOT_DELAY:-60}"
adb start-server >/dev/null 2>&1

RESTORE_SCRIPT="${ADB_RESTORE_SCRIPT:-$HOME/bin/restore-local-adb.sh}"

for _ in $(seq 1 "${ADB_BOOT_RETRIES:-24}"); do
  if "$RESTORE_SCRIPT"; then
    exit 0
  fi
  sleep "${ADB_BOOT_RETRY_DELAY:-5}"
done

exit 1
