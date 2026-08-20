# AGENTS.md

MemWatch is a Git-tracked Bash project. It has no build system, package manager,
or external test framework. ShellCheck is not installed — syntax-check scripts
with `bash -n file.sh` and run the repository test runner with
`bash tests/memwatch_test.sh`.

## Scripts

- `memwatch.sh` — infinite RAM and swap monitor (only exits via signal; never run without a timeout). Reads `/proc/meminfo` directly with `awk`, uses hysteresis, logs through standard output/journald, and can open desktop notifications and Zenity dialogs.
- `tests/memwatch_test.sh` — non-destructive Bash test runner for calculations, pressure logic, formatting, logging, process identity, grouping, and PID lookup. It does not restart the service or close applications.
- `systemd/memwatch.service` — tracked user-service template for the repository checkout; `install.sh` renders the installed user-local path.
- `config/memwatch.config.example` — tracked example containing every current configuration setting.
- `install.sh` — installs the monitor, service unit, and config example under the user’s home directories without starting the service.
- `uninstall.sh` — removes installed program and service files; preserves personal config unless `--purge` is supplied.

The scripts use Bash 5.x features such as arrays and process substitution, so
run them with Bash, not `sh`. `memwatch.sh` runs its monitor only when executed
directly; the test runner sources it to exercise individual functions safely.

## Notes

- `.github/` instruction files target GitHub Copilot + the Mermaid VS Code extension (`mermaidChart.*` commands); those tools do not exist in this OpenCode environment — ignore unless the user explicitly asks for Mermaid diagram work.
- `memwatch.sh` is the monitor deliverable. The tracked service and config files
  are templates; the active user-level unit and personal configuration remain
  installed outside the repository under `~/.config`.
- `install.sh` and `uninstall.sh` are deployment tools. Do not run them, reload
  systemd, or restart the service unless the user explicitly requests deployment.
