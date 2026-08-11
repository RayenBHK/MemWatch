# MemWatch

MemWatch is a lightweight Linux memory monitor written in Bash.

It watches system RAM usage, sends a desktop notification when memory crosses a configured threshold, and opens an interactive process picker so the user can review and close memory-heavy applications.

The project is designed to stay simple, transparent, and beginner-friendly while still behaving like a real desktop utility.

## Features

- Monitors RAM usage continuously
- Uses `MemAvailable` from `/proc/meminfo`
- Configurable warning and reset thresholds
- Hysteresis to prevent repeated alerts near the threshold
- Desktop notifications through `notify-send`
- Interactive process picker using Zenity
- Groups processes by application name
- Shows combined application RAM usage
- Graceful shutdown using `SIGTERM`
- Optional force-close using `SIGKILL`
- Verifies whether processes actually terminated
- Lightweight Bash implementation

## Current behavior

By default, MemWatch checks memory every 5 seconds.

```text
RAM < 80%
    normal state

RAM >= 85%
    desktop warning
    process picker opens

RAM <= 80%
    warning state resets

## License

MemWatch is licensed under the MIT License. See `LICENSE` for details.