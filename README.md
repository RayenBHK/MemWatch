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

MemWatch groups processes by command name and displays their combined memory usage:

```text
chrome    1.5 GiB
```

This makes it easier to identify which applications are consuming the most memory.

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
  - `pgrep`
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

Run MemWatch:

```bash
./memwatch.sh
```

Stop it with:

```text
Ctrl+C
```

## Configuration

Configuration is currently defined near the top of `memwatch.sh`.

```bash
WARNING_THRESHOLD=85
RESET_THRESHOLD=80
CHECK_INTERVAL=5
PROCESS_LIMIT=10
```

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

## Project structure

```text
MemWatch/
├── .gitignore
├── AGENTS.md
├── LICENSE
├── README.md
└── memwatch.sh
```

## Project status

MemWatch is currently an early working prototype.

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

The project is still under active development.

## Planned improvements

Future versions may include:

- systemd user service
- automatic startup on login
- configuration file under `~/.config/memwatch/`
- swap usage monitoring
- Linux PSI memory-pressure monitoring
- better application identification
- improved handling of helper processes
- application icons
- logging
- install and uninstall scripts
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