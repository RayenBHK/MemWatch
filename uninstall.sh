#!/usr/bin/env bash

set -euo pipefail

PURGE_CONFIG=false

case "${1:-}" in
    '') ;;
    --purge)
        PURGE_CONFIG=true
        ;;
    --help|-h)
        printf 'Usage: %s [--purge]\n' "$(basename "$0")"
        printf 'Remove the installed MemWatch files.\n'
        printf -- '--purge also removes the personal configuration.\n'
        exit 0
        ;;
    *)
        printf 'Unknown option: %s\n' "$1" >&2
        printf 'Usage: %s [--purge]\n' "$(basename "$0")" >&2
        exit 2
        ;;
esac

INSTALL_ROOT="$HOME/.local/share/memwatch"
CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/memwatch"
SYSTEMD_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

if command -v systemctl >/dev/null 2>&1; then
    if ! systemctl --user show-environment >/dev/null 2>&1; then
        printf 'ERROR: Cannot connect to the user systemd manager; refusing to remove the service files.\n' >&2
        exit 1
    fi

    if systemctl --user is-active --quiet memwatch; then
        systemctl --user stop memwatch
        printf 'Stopped the MemWatch user service.\n'
    fi

    if systemctl --user is-enabled --quiet memwatch; then
        systemctl --user disable memwatch
        printf 'Disabled MemWatch at login.\n'
    fi
else
    printf 'WARNING: systemctl is not installed; the service may need manual cleanup.\n' >&2
fi

rm -f "$INSTALL_ROOT/memwatch.sh"
rm -f "$SYSTEMD_ROOT/memwatch.service"

if [[ "$PURGE_CONFIG" == true ]]; then
    rm -f "$CONFIG_ROOT/config"
    printf 'Removed the personal configuration.\n'
else
    printf 'Preserved the personal configuration at %s/config\n' "$CONFIG_ROOT"
fi

if command -v systemctl >/dev/null 2>&1; then
    if systemctl --user daemon-reload; then
        printf 'Reloaded the user systemd units.\n'
    else
        printf 'WARNING: Could not reload user systemd units.\n' >&2
    fi
fi

rmdir "$INSTALL_ROOT" 2>/dev/null || true

printf 'MemWatch installation files were removed.\n'
