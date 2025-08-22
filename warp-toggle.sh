#!/usr/bin/env bash

################################################################################
# Name: warp-toggle.sh — Toggle Cloudflare WARP on macOS
#
# Purpose:
#   Cloudflare WARP on macOS may automatically re-enable itself after a manual
#   disconnect (e.g., due to org policy). This script toggles the WARP connection
#   and starts/stops the WARP launch daemon as needed.
#
# Description:
#   - If status shows "Connected": disconnect, wait 5s, then bootout the daemon.
#   - If status shows "Unable to connect to CloudflareWARP daemon": bootstrap
#     the daemon, then connect.
#   - Otherwise: print status and take no action.
#
# Usage: ./warp-toggle.sh
# Requires: sudo; launchctl; Cloudflare WARP app/CLI installed
# Daemon plist: /Library/LaunchDaemons/com.cloudflare.1dot1dot1dot1.macos.warp.daemon.plist
#
# Author: Cory Solovewicz
# Repo: https://github.com/corysolovewicz/warp-toggle
# Date: 2025-08-22
################################################################################

WARP_CLI="/Applications/Cloudflare WARP.app/Contents/Resources/warp-cli"
DAEMON_PLIST="/Library/LaunchDaemons/com.cloudflare.1dot1dot1dot1.macos.warp.daemon.plist"
DAEMON_LABEL="com.cloudflare.1dot1dot1dot1.macos.warp.daemon"

if [[ $(uname -s) != "Darwin" ]]; then
  echo "This script is for macOS." >&2; exit 1
fi
if [[ ! -x "$WARP_CLI" ]]; then
  echo "warp-cli not found at: $WARP_CLI" >&2; exit 1
fi
if [[ ! -f "$DAEMON_PLIST" ]]; then
  echo "LaunchDaemon plist not found at: $DAEMON_PLIST" >&2; exit 1
fi

sudo -v || { echo "sudo authentication failed." >&2; exit 1; }

status_out="$("$WARP_CLI" status 2>&1)"
echo "$status_out"

if echo "$status_out" | grep -qi 'Unable to connect to CloudflareWARP daemon'; then
  echo "[action] Daemon not reachable -> start daemon, then connect"
  sudo launchctl bootstrap system "$DAEMON_PLIST" || true
  sudo launchctl kickstart -k "system/$DAEMON_LABEL" || true

  # brief wait for daemon
  for _ in {1..10}; do
    sleep 0.2
    if ! "$WARP_CLI" status 2>&1 | grep -qi 'Unable to connect to CloudflareWARP daemon'; then
      break
    fi
  done

  if ! sudo "$WARP_CLI" connect; then
    echo "warp-cli connect failed." >&2
    exit 1
  fi
  echo "[done] Connected and daemon started."

elif echo "$status_out" | grep -qi 'Connected'; then
  echo "[action] Connected -> disconnect, wait 5s, then stop daemon"
  if ! sudo "$WARP_CLI" disconnect; then
    echo "warp-cli disconnect failed (policy may enforce always-on). Proceeding anyway…" >&2
  fi
  sleep 5
  sudo launchctl bootout system "$DAEMON_PLIST" || true
  echo "[done] Disconnected and daemon stopped."

else
  echo "[info] Daemon reachable but not connected. No action taken."
  echo "       (To stop the daemon now, run:"
  echo "        sudo launchctl bootout system \"$DAEMON_PLIST\")"
fi

