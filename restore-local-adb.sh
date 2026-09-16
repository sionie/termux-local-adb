#!/data/data/com.termux/files/usr/bin/bash

set -u

ADB="${ADB:-adb}"
CACHE="${CACHE:-$HOME/.cache/termux-local-adb/adb-serial}"
LOG="${LOG:-$HOME/.cache/termux-local-adb/restore.log}"
START_PORT="${START_PORT:-30000}"
END_PORT="${END_PORT:-49999}"
PROBE_SECONDS="${PROBE_SECONDS:-10}"
DISCOVERY_HOSTS="${ADB_DISCOVERY_HOSTS:-127.0.0.1}"
TARGET_SERIAL="127.0.0.1:5555"

mkdir -p "$(dirname "$CACHE")" "$(dirname "$LOG")"

log() {
  printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG" >&2
}

verify_serial() {
  local serial="$1" state model
  state="$($ADB -s "$serial" get-state 2>/dev/null || true)"
  [ "$state" = "device" ] || return 1
  model="$($ADB -s "$serial" shell getprop ro.product.model 2>/dev/null | tr -d '\r' || true)"
  [ -n "$model" ]
}

try_serial() {
  local serial="$1" out

  if verify_serial "$serial"; then
    printf '%s\n' "$serial"
    return 0
  fi

  out="$($ADB connect "$serial" 2>&1 || true)"
  log "try $serial -> $out"
  sleep 1

  if verify_serial "$serial"; then
    printf '%s\n' "$serial"
    return 0
  fi

  $ADB disconnect "$serial" >/dev/null 2>&1 || true
  return 1
}

promote_to_5555() {
  local source_serial="$1"

  log "promoting $source_serial to tcpip 5555"
  $ADB -s "$source_serial" tcpip 5555 >/dev/null 2>&1 || return 1
  sleep 2
  $ADB connect "$TARGET_SERIAL" >/dev/null 2>&1 || true
  sleep 1
  verify_serial "$TARGET_SERIAL"
}

probe_ports() {
  local host="$1"
  python - "$host" "$START_PORT" "$END_PORT" "$PROBE_SECONDS" <<'PY'
import errno
import select
import socket
import sys
import time

host = sys.argv[1]
start = int(sys.argv[2])
end = int(sys.argv[3])
deadline = time.time() + float(sys.argv[4])
batch = 512
seen = set()

for base in range(start, end + 1, batch):
    if time.time() >= deadline:
        break

    socks = []
    poller = select.poll()
    fdmap = {}

    for port in range(base, min(base + batch, end + 1)):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.setblocking(False)
            rc = s.connect_ex((host, port))

            if rc == 0:
                if port not in seen:
                    print(port, flush=True)
                    seen.add(port)
                s.close()
                continue

            if rc in (errno.EINPROGRESS, errno.EALREADY, errno.EWOULDBLOCK):
                poller.register(s, select.POLLOUT | select.POLLERR | select.POLLHUP)
                fdmap[s.fileno()] = (s, port)
                socks.append(s)
            else:
                s.close()
        except Exception:
            pass

    wait_ms = int(1000 * min(0.15, max(0, deadline - time.time())))
    if socks and wait_ms > 0:
        for fd, _ in poller.poll(wait_ms):
            item = fdmap.get(fd)
            if not item:
                continue
            s, port = item
            try:
                if s.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR) == 0:
                    if port not in seen:
                        print(port, flush=True)
                        seen.add(port)
            except Exception:
                pass

    for s in socks:
        try:
            s.close()
        except Exception:
            pass
PY
}

# 1) Persistent localhost ADB is already alive.
if verify_serial "$TARGET_SERIAL"; then
  serial="$TARGET_SERIAL"
  log "OK existing $serial"
else
  serial=""

  # 2) Reuse any already-connected dynamic ADB transport.
  existing="$($ADB devices 2>/dev/null | awk '$2=="device" && $1 ~ /:[0-9]+$/ && $1 !~ /:5555$/ {print $1; exit}')"
  if [ -n "$existing" ]; then
    dynamic_serial="$(try_serial "$existing" || true)"
    if [ -n "$dynamic_serial" ] && promote_to_5555 "$dynamic_serial"; then
      serial="$TARGET_SERIAL"
    fi
  fi

  # 3) Try the last verified endpoint.
  if [ -z "$serial" ] && [ -r "$CACHE" ]; then
    cached="$(head -n1 "$CACHE")"
    if [ "$cached" != "$TARGET_SERIAL" ]; then
      log "trying cached $cached"
      dynamic_serial="$(try_serial "$cached" || true)"
      if [ -n "$dynamic_serial" ] && promote_to_5555 "$dynamic_serial"; then
        serial="$TARGET_SERIAL"
      fi
    fi
  fi

  # 4) Probe likely Wireless Debugging ports and verify each candidate with ADB.
  if [ -z "$serial" ]; then
    for host in $DISCOVERY_HOSTS; do
      candidates="$(probe_ports "$host" 2>/dev/null || true)"
      log "open-port candidates on $host: $(printf '%s' "$candidates" | tr '\n' ' ')"

      while IFS= read -r port; do
        [ -n "$port" ] || continue

        # Always try loopback first for a locally hosted adbd endpoint.
        dynamic_serial="$(try_serial "127.0.0.1:$port" || true)"
        if [ -z "$dynamic_serial" ] && [ "$host" != "127.0.0.1" ]; then
          dynamic_serial="$(try_serial "$host:$port" || true)"
        fi
        [ -n "$dynamic_serial" ] || continue

        if promote_to_5555 "$dynamic_serial"; then
          serial="$TARGET_SERIAL"
          break
        fi
      done <<EOF_PORTS
$candidates
EOF_PORTS

      [ -n "$serial" ] && break
    done
  fi
fi

if [ -z "$serial" ]; then
  log "ERROR no verified ADB endpoint"
  exit 1
fi

printf '%s\n' "$serial" > "$CACHE"

# Remove stale dynamic transports from the local adb client list.
$ADB devices 2>/dev/null |
awk '$1 ~ /:[0-9]+$/ && $1 !~ /:5555$/ {print $1}' |
while IFS= read -r stale; do
  [ -n "$stale" ] || continue
  $ADB disconnect "$stale" >/dev/null 2>&1 || true
done

# Optional Android phantom-process mitigations. Ignore failures on unsupported builds.
$ADB -s "$serial" shell settings put global \
  settings_enable_monitor_phantom_procs false >/dev/null 2>&1 || true
$ADB -s "$serial" shell device_config put activity_manager \
  max_phantom_processes 2147483647 >/dev/null 2>&1 || true

log "DONE $serial phantom-process settings applied"
printf '%s\n' "$serial"
