# MemWatch

MemWatch is a lightweight Linux memory monitor written in Bash.

It continuously watches system RAM usage, sends a desktop notification when memory crosses a configurable threshold, and opens an interactive process picker so the user can review and close memory-heavy applications.

The goal is to provide a simple, transparent, and user-controlled alternative to automatic OOM killers.

## Features

- Continuous RAM monitoring
- Uses `MemAvailable` from `/proc/meminfo`
- Configurable warning and reset thresholds
- Hysteresis to prevent repeated alerts near the threshold
- Desktop notifications through `notify-send`
- Interactive process picker using Zenity
- Groups processes by application name
- Shows combined RAM usage per application
- Graceful application shutdown using `SIGTERM`
- Optional force-close using `SIGKILL`
- Verifies whether processes actually terminated
- Lightweight Bash implementation
- No background framework or heavy runtime required

## How it works

By default, MemWatch checks memory usage every 5 seconds.

```text
RAM < 80%
    Normal state

RAM >= 85%
    Desktop warning
    Process picker opens

RAM <= 80%
    Warning state resets
```

The separate warning and reset thresholds create a small hysteresis range.

This prevents MemWatch from repeatedly triggering if RAM usage fluctuates around the warning threshold.

For example:

```text
84% → normal
86% → warning triggered
84% → no new warning
82% → no new warning
79% → warning state reset
86% → warning can trigger again
```

## Memory calculation

MemWatch reads memory information directly from:

```text
/proc/meminfo
```

It uses:

```text
MemTotal
MemAvailable
```

Approximate used RAM is calculated as:

```text
used RAM = MemTotal - MemAvailable
```

This is preferable to relying on `MemFree`, because Linux intentionally uses otherwise-unused RAM for filesystem caches and other reclaimable data.

## Application grouping

Modern Linux applications often use multiple processes.

For example, a Chromium-based browser may create separate processes for:

- the main browser
- tabs and renderers
- GPU tasks
- extensions
- utility processes

Instead of showing:

```text
chrome    650 MiB
chrome    420 MiB
chrome    310 MiB
chrome    180 MiB
```

MemWatch resolves each process through `/proc/<pid>/exe`, groups processes that
run the same executable, and displays their combined memory usage:

```text
chrome    1.5 GiB
```

This makes it easier to identify which applications are consuming the most memory.

The executable identity is kept in a hidden picker column. Therefore, two
different executables with the same visible filename are not accidentally
treated as one application. This also avoids the 15-character name limit of
Linux's `comm` field.

Interpreted scripts receive a more specific identity when possible. For
example, `bash backup.sh` is grouped by the Bash executable and the resolved
`backup.sh` path instead of being combined with every other Bash process.

Processes that exit during inspection or whose executable information is not
accessible are safely skipped. Before closing anything, MemWatch scans `/proc`
again so that it operates on the application's current processes rather than
an old PID list.

## Process management

When memory usage crosses the configured warning threshold, MemWatch opens a Zenity dialog containing the highest memory-consuming application groups.

The user chooses which application to close.

MemWatch first attempts a graceful shutdown using:

```bash
kill <pid>
```

which sends `SIGTERM`.

If processes remain alive after the shutdown attempt, MemWatch can offer the user an explicit force-close option using:

```bash
kill -9 <pid>
```

which sends `SIGKILL`.

`SIGKILL` is never used automatically.

## Requirements

MemWatch currently requires:

- Bash
- `procps`
  - `ps`
- `readlink`
- `awk`
- `notify-send`
- Zenity

On Ubuntu-based distributions:

```bash
sudo apt install procps libnotify-bin zenity
```

## Installation

Clone the repository:

```bash
git clone https://github.com/RayenBHK/MemWatch
cd MemWatch
```

Make the script executable:

```bash
chmod +x memwatch.sh
```

Install MemWatch for your user account:

```bash
./install.sh
```

The installer places the monitor at:

```text
~/.local/share/memwatch/memwatch.sh
```

It installs the user service at:

```text
~/.config/systemd/user/memwatch.service
```

and creates the personal configuration at:

```text
~/.config/memwatch/config
```

An existing personal configuration is preserved. The installer reloads the
user systemd definitions but does not start MemWatch automatically.

Enable MemWatch at login and start it manually:

```bash
systemctl --user enable --now memwatch
```

Check the service and its journal:

```bash
systemctl --user status memwatch
journalctl --user -u memwatch
```

To uninstall the installed program and service:

```bash
./uninstall.sh
```

The normal uninstall preserves your personal configuration. To remove that
configuration too, use:

```bash
./uninstall.sh --purge
```

Alternatively, run the repository copy directly during development:

```bash
./memwatch.sh
```

Stop it with:

```text
Ctrl+C
```

## Configuration

MemWatch reads optional settings from:

```text
~/.config/memwatch/config
```

The repository provides a complete starting point at
`config/memwatch.config.example`. Copy it to the path above and edit the
values for your user session.

If the file does not exist or omits a setting, MemWatch uses the defaults
defined near the top of `memwatch.sh`:

```bash
WARNING_THRESHOLD=85
RESET_THRESHOLD=80
SWAP_WARNING_THRESHOLD=90
SWAP_RESET_THRESHOLD=80
PSI_SOME_WARNING_THRESHOLD=10.0
PSI_SOME_RESET_THRESHOLD=1.0
CHECK_INTERVAL=5
PROCESS_LIMIT=10
```

Configuration values are read as data. Unknown keys and malformed lines are
ignored, and invalid values are replaced with their safe defaults. PSI values
are decimal percentages; the other thresholds are integer percentages.

### `WARNING_THRESHOLD`

RAM usage percentage that triggers MemWatch.

Default:

```text
85%
```

### `RESET_THRESHOLD`

RAM usage must fall to this percentage before another warning can be triggered.

Default:

```text
80%
```

### `SWAP_WARNING_THRESHOLD`

Swap usage percentage that can trigger MemWatch when RAM is also at or above
`RESET_THRESHOLD`. High swap does not trigger an alert by itself because
occupied swap can remain high after memory pressure has passed.

Default:

```text
90%
```

### `SWAP_RESET_THRESHOLD`

Swap usage percentage used to re-arm alerts while RAM is at
`RESET_THRESHOLD`. RAM falling below `RESET_THRESHOLD` also re-arms alerts,
even if swap remains occupied.

Default:

```text
80%
```

### `PSI_SOME_WARNING_THRESHOLD`

Linux memory PSI `some avg10` percentage that triggers a pressure warning when
PSI is available.

Default:

```text
10.0%
```

### `PSI_SOME_RESET_THRESHOLD`

Linux memory PSI `some avg10` percentage at or below which PSI pressure is
considered reset.

Default:

```text
1.0%
```

### `CHECK_INTERVAL`

Number of seconds between memory checks.

Default:

```text
5 seconds
```

### `PROCESS_LIMIT`

Maximum number of application groups shown in the process picker.

Default:

```text
10
```

## Logging

MemWatch records memory readings, RAM/swap/PSI pressure alerts, application
selections, close requests, cancellations, and failures. Each event includes
an `INFO`, `WARNING`, or `ERROR` label.

When MemWatch runs as a systemd user service, view recent events with:

```bash
journalctl --user -u memwatch
```

Follow events live with:

```bash
journalctl --user -u memwatch -f
```

When the script is run directly, the same events appear in the terminal.

## Testing

MemWatch includes a standalone Bash test runner. It does not require a test
framework, ShellCheck, Zenity, or a notification daemon.

Run it from the repository root:

```bash
bash tests/memwatch_test.sh
```

The test runner checks syntax, configuration validation, RAM and swap
calculations, PSI parsing, pressure thresholds, hysteresis, formatting,
logging, process identity, grouping, and PID lookup. It uses temporary
configuration, PSI, and process fixtures. It does not modify your real
configuration, restart the systemd service, or close any application.

The installer and uninstaller are also tested in isolated temporary user
directories; those tests do not touch your real home directory.

## Project structure

```text
MemWatch/
├── .gitignore
├── AGENTS.md
├── config/
│   └── memwatch.config.example
├── LICENSE
├── README.md
├── install.sh
├── memwatch.sh
├── systemd/
│   └── memwatch.service
├── tests/
│   └── memwatch_test.sh
└── uninstall.sh
```

## Project status

MemWatch v0.1.0 is the first usable release. It is a lightweight Bash utility
for monitoring RAM, swap, and Linux memory PSI pressure, with user-controlled
desktop alerts and process management.

The core workflow is functional:

```text
Monitor RAM
    ↓
Detect threshold
    ↓
Send notification
    ↓
Show application list
    ↓
User selects application
    ↓
SIGTERM
    ↓
Verify shutdown
    ↓
Optional SIGKILL
```

The project remains under active development, but the core monitoring,
configuration, testing, installation, and user-service workflows are now
documented and reproducible.

## Planned improvements

Future versions may include:

- improved handling of helper processes
- application icons
- packaging for Linux distributions
- improved desktop integration
- configurable notification behavior

## Development goals

MemWatch is intentionally written in Bash to stay lightweight and to explore core Linux concepts such as:

- `/proc`
- processes and PIDs
- signals
- RSS memory usage
- pipelines
- Bash arrays
- process substitution
- desktop notifications
- process management
- system monitoring
- application grouping

Repository-specific development guidance can be found in `AGENTS.md`.

## License

MemWatch is licensed under the MIT License.

See [`LICENSE`](LICENSE) for details.
