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