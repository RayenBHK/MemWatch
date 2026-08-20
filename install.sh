#!/usr/bin/env bash

set -euo pipefail

REPOSITORY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INSTALL_ROOT="$HOME/.local/share/memwatch"
CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/memwatch"
SYSTEMD_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

install -Dm755 \
    "$REPOSITORY_ROOT/memwatch.sh" \
    "$INSTALL_ROOT/memwatch.sh"

install -Dm644 \
    "$REPOSITORY_ROOT/systemd/memwatch.service" \
    "$SYSTEMD_ROOT/memwatch.service"

sed -i \
    's|^ExecStart=.*|ExecStart=%h/.local/share/memwatch/memwatch.sh|' \
    "$SYSTEMD_ROOT/memwatch.service"

if [[ ! -e "$CONFIG_ROOT/config" ]]; then
    install -Dm644 \
        "$REPOSITORY_ROOT/config/memwatch.config.example" \
        "$CONFIG_ROOT/config"
    printf 'Installed a new configuration at %s\n' "$CONFIG_ROOT/config"
else
    printf 'Preserved existing configuration at %s\n' "$CONFIG_ROOT/config"
fi

if command -v systemctl >/dev/null 2>&1; then
    if systemctl --user daemon-reload; then
        printf 'Reloaded the user systemd units.\n'
    else
        printf 'WARNING: Could not reload user systemd units.\n' >&2
    fi
else
    printf 'WARNING: systemctl is not installed; reload the user unit manually.\n' >&2
fi

printf '\nMemWatch was installed to %s\n' "$INSTALL_ROOT/memwatch.sh"
printf 'The service is not started automatically by this script.\n'
printf 'Start it with: systemctl --user enable --now memwatch\n'
