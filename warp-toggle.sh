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

# Absolute path to the Cloudflare WARP CLI within the app bundle.
WARP_CLI="/Applications/Cloudflare WARP.app/Contents/Resources/warp-cli"

# LaunchDaemon definition installed by the WARP app. This controls the system service.
DAEMON_PLIST="/Library/LaunchDaemons/com.cloudflare.1dot1dot1dot1.macos.warp.daemon.plist"

# The launchd label for the WARP daemon. Used with kickstart.
DAEMON_LABEL="com.cloudflare.1dot1dot1dot1.macos.warp.daemon"

# Guard: script is only intended for macOS (Darwin).
if [[ $(uname -s) != "Darwin" ]]; then
  echo "This script is for macOS." >&2; exit 1
fi

# Guard: ensure the WARP CLI exists and is executable.
if [[ ! -x "$WARP_CLI" ]]; then
  echo "warp-cli not found at: $WARP_CLI" >&2; exit 1
fi

# Guard: ensure the LaunchDaemon plist exists.
if [[ ! -f "$DAEMON_PLIST" ]]; then
  echo "LaunchDaemon plist not found at: $DAEMON_PLIST" >&2; exit 1
fi

# Cache sudo credentials once up front so later sudo calls do not re-prompt.
sudo -v || { echo "sudo authentication failed." >&2; exit 1; }

# Query current WARP status. stderr is captured as some errors are printed there.
status_out="$("$WARP_CLI" status 2>&1)"

# Echo the raw status for observability.
echo "$status_out"

# Branch 1: Daemon not reachable. Start daemon first, then connect.
if echo "$status_out" | grep -qi 'Unable to connect to CloudflareWARP daemon'; then
  echo "[action] Daemon not reachable -> start daemon, then connect"

  # Load the LaunchDaemon into the system domain. Harmless if already loaded.
  sudo launchctl bootstrap system "$DAEMON_PLIST" || true

  # Ensure the job is started immediately even if already loaded.
  sudo launchctl kickstart -k "system/$DAEMON_LABEL" || true

  # Wait briefly for the daemon to come up and accept CLI connections.
  for _ in {1..10}; do
    sleep 0.2
    if ! "$WARP_CLI" status 2>&1 | grep -qi 'Unable to connect to CloudflareWARP daemon'; then
      break
    fi
  done

  # Now that the daemon is up, connect WARP.
  if ! sudo "$WARP_CLI" connect; then
    echo "warp-cli connect failed." >&2
    exit 1
  fi
  echo "[done] Connected and daemon started."

# Branch 2: Currently connected. Disconnect first, wait 5s, then stop the daemon.
elif echo "$status_out" | grep -qi 'Connected'; then
  echo "[action] Connected -> disconnect, wait 5s, then stop daemon"

  # Disconnect WARP. In some managed environments this may be blocked by policy.
  if ! sudo "$WARP_CLI" disconnect; then
    echo "warp-cli disconnect failed (policy may enforce always-on). Proceeding anyway…" >&2
  fi

  # Allow time for routes, DNS, and device state to settle before stopping the service.
  sleep 5

  # Unload and stop the LaunchDaemon from the system domain.
  sudo launchctl bootout system "$DAEMON_PLIST" || true
  echo "[done] Disconnected and daemon stopped."

# Branch 3: Daemon reachable but not connected. Do nothing unless the user wants otherwise.
else
  echo "[info] Daemon reachable but not connected. No action taken."
  echo "       (To stop the daemon now, run:"
  echo "        sudo launchctl bootout system \"$DAEMON_PLIST\")"
fi
