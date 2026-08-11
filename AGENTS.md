# AGENTS.md

Two standalone Bash scripts. No build system, no tests, no lint config, no package manager, not a git repo. Shellcheck is not installed — syntax-check with `bash -n file.sh`.

## Scripts

- `memwatch.sh` — infinite RAM-monitor loop (only exits via signal; never run without a timeout). Reads `/proc/meminfo` directly (awk), not `free`. Tunables are plain constants at the top: `WARNING_THRESHOLD=70`, `RESET_THRESHOLD=65`, `CHECK_INTERVAL=5`. Hysteresis: warns once at ≥70%, re-arms only below ≤65%. Alerting uses `notify-send`, so it requires a running desktop notification daemon — it fails silently headless.
- `process-test.sh` — interactive prototype: lists top-10 processes by RSS via `ps -eo pid=,%mem=,comm= --sort=-rss`, lets the user pick one in a `zenity` dialog (GUI required; `zenity` must be installed), then prints `Selected PID: <pid>`.

Neither script takes arguments. Both use bash 5.x features (arrays, process substitution), so run with `bash script.sh`, not `sh`.

## Notes

- `.github/` instruction files target GitHub Copilot + the Mermaid VS Code extension (`mermaidChart.*` commands); those tools do not exist in this OpenCode environment — ignore unless the user explicitly asks for Mermaid diagram work.
- No README; `memwatch.sh` is the deliverable, `process-test.sh` is an experiment for adding interactive process selection.
