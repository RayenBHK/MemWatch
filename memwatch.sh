#!/usr/bin/env bash

# =========================
# Configuration
# =========================

WARNING_THRESHOLD=80
RESET_THRESHOLD=75
CHECK_INTERVAL=5
PROCESS_LIMIT=10

WARNING_SENT=false


# =========================
# Memory
# =========================

get_memory_usage() {
    MEM_TOTAL=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    MEM_AVAILABLE=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)

    MEM_USED=$((MEM_TOTAL - MEM_AVAILABLE))
    MEM_USED_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))
}


# =========================
# Notifications
# =========================

show_warning() {
    notify-send \
        -u critical \
        "MemWatch" \
        "RAM usage has reached ${MEM_USED_PERCENT}%."
}


# =========================
# RAM formatting
# =========================

format_ram() {
    local rss="$1"

    if (( rss >= 1048576 )); then
        awk -v rss="$rss" \
            'BEGIN { printf "%.1f GiB", rss / 1048576 }'
    else
        awk -v rss="$rss" \
            'BEGIN { printf "%.0f MiB", rss / 1024 }'
    fi
}


# =========================
# Process list
# =========================

build_process_list() {
    PROCESS_ARGS=()

    while read -r RSS PROCESS; do
        RAM=$(format_ram "$RSS")

        PROCESS_ARGS+=(
            "$PROCESS"
            "$RAM"
        )

    done < <(
        ps -eo comm=,rss= |
            awk '
                {
                    memory[$1] += $2
                }
                END {
                    for (process in memory) {
                        print memory[process], process
                    }
                }
            ' |
            sort -nr |
            head -n "$PROCESS_LIMIT"
    )
}


# =========================
# Process picker
# =========================

show_process_picker() {
    SELECTED_PROCESS=$(zenity \
        --list \
        --title="MemWatch" \
        --text="RAM usage is ${MEM_USED_PERCENT}%.

Select an application:" \
        --column="Application" \
        --column="RAM" \
        --width=650 \
        --height=400 \
        "${PROCESS_ARGS[@]}")
}


# =========================
# Process helpers
# =========================

process_exists() {
    local pid="$1"

    kill -0 "$pid" 2>/dev/null
}


get_process_pids() {
    local process_name="$1"

    pgrep -x "$process_name"
}


# =========================
# Force close
# =========================

force_close_process() {
    local pid="$1"
    local process_name="$2"

    if zenity \
        --question \
        --title="MemWatch" \
        --text="$process_name is still running.

Do you want to force close it?" \
        --ok-label="Force Close" \
        --cancel-label="Leave Running"; then

        kill -9 "$pid"

        sleep 1

        if process_exists "$pid"; then
            notify-send \
                -u critical \
                "MemWatch" \
                "Failed to force close $process_name."
        else
            notify-send \
                "MemWatch" \
                "$process_name was force closed."
        fi
    fi
}


# =========================
# Close process
# =========================

close_process() {
    local pid="$1"

    # The process may have disappeared since the picker opened.
    if ! process_exists "$pid"; then
        notify-send \
            "MemWatch" \
            "The selected process is no longer running."

        return
    fi

    local process_name
    process_name=$(ps -p "$pid" -o comm=)

    if zenity \
        --question \
        --title="MemWatch" \
        --text="Close $process_name (PID $pid)?" \
        --ok-label="Close Process" \
        --cancel-label="Cancel"; then

        kill "$pid"

        # Give SIGTERM some time to work.
        sleep 2

        if process_exists "$pid"; then
            force_close_process "$pid" "$process_name"
        else
            notify-send \
                "MemWatch" \
                "$process_name closed successfully."
        fi
    fi
}


# =========================
# Close process group
# =========================

close_process_group() {
    local process_name="$1"

    mapfile -t pids < <(get_process_pids "$process_name")

    local process_count="${#pids[@]}"

    if (( process_count == 0 )); then
        notify-send \
            "MemWatch" \
            "$process_name is no longer running."

        return
    fi

    if zenity \
        --question \
        --title="MemWatch" \
        --text="Close $process_name?

This will send a close request to $process_count process(es)." \
        --ok-label="Close Application" \
        --cancel-label="Cancel"; then

        kill "${pids[@]}" 2>/dev/null

        sleep 2

        mapfile -t remaining_pids < <(get_process_pids "$process_name")

        if (( ${#remaining_pids[@]} == 0 )); then
            notify-send \
                "MemWatch" \
                "$process_name closed successfully."

        else
            if zenity \
                --question \
                --title="MemWatch" \
                --text="$process_name still has ${#remaining_pids[@]} process(es) running.

Do you want to force close the remaining processes?" \
                --ok-label="Force Close Remaining" \
                --cancel-label="Leave Running"; then

                kill -9 "${remaining_pids[@]}" 2>/dev/null

                sleep 1

                mapfile -t final_pids < <(get_process_pids "$process_name")

                if (( ${#final_pids[@]} == 0 )); then
                    notify-send \
                        "MemWatch" \
                        "$process_name was force closed."
                else
                    notify-send \
                        -u critical \
                        "MemWatch" \
                        "Failed to close ${#final_pids[@]} $process_name process(es)."
                fi
            fi
        fi
    fi
}


# =========================
# High-memory handler
# =========================

handle_high_memory() {
    show_warning

    build_process_list

    show_process_picker

    if [[ -z "$SELECTED_PROCESS" ]]; then
        return
    fi

    close_process_group "$SELECTED_PROCESS"
}


# =========================
# Main loop
# =========================

main() {
    while true; do
        get_memory_usage

        echo "RAM usage: ${MEM_USED_PERCENT}%"

        if (( MEM_USED_PERCENT >= WARNING_THRESHOLD )); then

            if [[ "$WARNING_SENT" == false ]]; then
                WARNING_SENT=true

                handle_high_memory
            fi

        elif (( MEM_USED_PERCENT <= RESET_THRESHOLD )); then
            WARNING_SENT=false
        fi

        sleep "$CHECK_INTERVAL"
    done
}


main