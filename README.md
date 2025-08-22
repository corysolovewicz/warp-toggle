# warp-toggle

Shell script for reliably toggling Cloudflare WARP on macOS from the terminal.

The script enforces correct order of operations:
- Connect path: start the launch daemon, then connect.
- Disconnect path: disconnect, wait 5 seconds, then stop the launch daemon.

## What it does

- Checks current WARP status using the Cloudflare WARP CLI.
- If status contains `Unable to connect to CloudflareWARP daemon`, it starts the launch daemon and connects.
- If status contains `Connected`, it disconnects, waits 5 seconds, then stops the launch daemon.
- If the daemon is reachable but not connected, it prints status and takes no action.

## Requirements

- macOS with Cloudflare WARP installed
- `sudo` privileges
- `launchctl` available in the PATH

Defaults used by the script:
```text
WARP_CLI     = /Applications/Cloudflare WARP.app/Contents/Resources/warp-cli
DAEMON_PLIST = /Library/LaunchDaemons/com.cloudflare.1dot1dot1dot1.macos.warp.daemon.plist
DAEMON_LABEL = com.cloudflare.1dot1dot1dot1.macos.warp.daemon
```

## Install

Clone this repository and make the script executable.

```bash
git clone https://github.com/corysolovewicz/warp-toggle.git
cd warp-toggle
chmod +x warp-toggle.sh
```

Optional: add the repo directory to your PATH or move the script somewhere on your PATH.

```bash
sudo mv warp-toggle.sh /usr/local/bin/warp-toggle
```

## Usage

Run the script. You will be prompted for sudo once.

```bash
warp-toggle
```

Example output when the daemon is not running:
```text
Unable to connect to CloudflareWARP daemon. Maybe the daemon is not running?
[action] Daemon not reachable -> start daemon, then connect
[done] Connected and daemon started.
```

Example output when connected:
```text
Connected
[action] Connected -> disconnect, wait 5s, then stop daemon
[done] Disconnected and daemon stopped.
```

## Notes on behavior

- The 5 second delay after `disconnect` allows the client to tear down gracefully before the daemon is stopped.
- If your organization enforces always-on, `warp-cli disconnect` may fail with an authorization error. The script will still attempt to stop the daemon, but org policy may immediately restart or block changes.
- Quoted error text is matched case-insensitively.

## Troubleshooting

- If `warp-cli` is not found, verify the app path or update `WARP_CLI` at the top of the script.
- If `launchctl bootstrap` returns that the service is already loaded, this is harmless. The script uses `kickstart` to ensure it is started.
- If `launchctl bootout` says the service is not found, it is already stopped.
- If status is stuck on `Connecting` or `Pending`, try:
  ```bash
  sudo launchctl bootout system /Library/LaunchDaemons/com.cloudflare.1dot1dot1dot1.macos.warp.daemon.plist
  sudo launchctl bootstrap system /Library/LaunchDaemons/com.cloudflare.1dot1dot1dot1.macos.warp.daemon.plist
  sudo "/Applications/Cloudflare WARP.app/Contents/Resources/warp-cli" connect
  ```

## Uninstall

Remove the script and, if desired, unload the daemon.

```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.cloudflare.1dot1dot1dot1.macos.warp.daemon.plist
sudo rm -f /usr/local/bin/warp-toggle
```

Cloudflare also ships an uninstall script inside the app bundle:
```bash
sudo "/Applications/Cloudflare WARP.app/Contents/Resources/uninstall.sh"
```

## Development

The script is a single file. Feel free to open a PR to add:
- `--force-enable` to always start daemon and connect
- `--force-disable` to always disconnect and stop daemon
- `--verbose` logging

## License

GPL-3.0 license. See `LICENSE` in this repository.
