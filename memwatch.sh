#!/usr/bin/env bash

# =========================
# Configuration
# =========================

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/memwatch/config"

# Defaults
WARNING_THRESHOLD=85
RESET_THRESHOLD=80
SWAP_WARNING_THRESHOLD=90
SWAP_RESET_THRESHOLD=80
PSI_SOME_WARNING_THRESHOLD=10.0
PSI_SOME_RESET_THRESHOLD=1.0
CHECK_INTERVAL=5
PROCESS_LIMIT=10

WARNING_SENT=false
declare -A APPLICATION_NAMES=()
PSI_SOURCE="/proc/pressure/memory"
PSI_AVAILABLE=false
PSI_SOME_AVG10=0
PSI_FULL_AVG10=0


# =========================
# Logging
# =========================

log_event() {
    local level="$1"
    shift

    printf 'MemWatch [%s] %s\n' "$level" "$*"
}


# =========================
# Configuration
# =========================

is_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}


is_percentage() {
    local value="$1"

    [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
    awk -v value="$value" 'BEGIN { exit !(value >= 0 && value <= 100) }'
}


load_config() {
    local line
    local key
    local value

    [[ -f "$CONFIG_FILE" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"

        [[ -z "$line" || "$line" == \#* ]] && continue

        if [[ "$line" != *=* ]]; then
            log_event "WARNING" "Ignoring malformed configuration line."
            continue
        fi

        key="${line%%=*}"
        value="${line#*=}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"

        case "$key" in
            WARNING_THRESHOLD|RESET_THRESHOLD|SWAP_WARNING_THRESHOLD|SWAP_RESET_THRESHOLD|\
            PSI_SOME_WARNING_THRESHOLD|PSI_SOME_RESET_THRESHOLD|CHECK_INTERVAL|PROCESS_LIMIT)
                printf -v "$key" '%s' "$value"
                ;;
            *)
                log_event "WARNING" "Ignoring unknown configuration key: $key"
                ;;
        esac
    done < "$CONFIG_FILE"
}


use_default() {
    local key="$1"
    local default_value="$2"

    printf -v "$key" '%s' "$default_value"
    log_event "ERROR" "Invalid $key; using default $default_value."
}


validate_config() {
    if ! is_integer "$WARNING_THRESHOLD" || (( WARNING_THRESHOLD > 100 )); then
        use_default WARNING_THRESHOLD 85
    fi

    if ! is_integer "$RESET_THRESHOLD" || (( RESET_THRESHOLD > 100 )); then
        use_default RESET_THRESHOLD 80
    fi

    if ! is_integer "$SWAP_WARNING_THRESHOLD" || (( SWAP_WARNING_THRESHOLD > 100 )); then
        use_default SWAP_WARNING_THRESHOLD 90
    fi

    if ! is_integer "$SWAP_RESET_THRESHOLD" || (( SWAP_RESET_THRESHOLD > 100 )); then
        use_default SWAP_RESET_THRESHOLD 80
    fi

    if ! is_percentage "$PSI_SOME_WARNING_THRESHOLD"; then
        use_default PSI_SOME_WARNING_THRESHOLD 10.0
    fi

    if ! is_percentage "$PSI_SOME_RESET_THRESHOLD"; then
        use_default PSI_SOME_RESET_THRESHOLD 1.0
    fi

    if ! is_integer "$CHECK_INTERVAL" || (( CHECK_INTERVAL < 1 )); then
        use_default CHECK_INTERVAL 5
    fi

    if ! is_integer "$PROCESS_LIMIT" || (( PROCESS_LIMIT < 1 )); then
        use_default PROCESS_LIMIT 10
    fi

    if (( RESET_THRESHOLD > WARNING_THRESHOLD )); then
        use_default RESET_THRESHOLD 80
    fi

    if (( SWAP_RESET_THRESHOLD > SWAP_WARNING_THRESHOLD )); then
        use_default SWAP_RESET_THRESHOLD 80
    fi

    if ! awk -v reset="$PSI_SOME_RESET_THRESHOLD" \
            -v warning="$PSI_SOME_WARNING_THRESHOLD" \
            'BEGIN { exit !(reset <= warning) }'; then
        use_default PSI_SOME_RESET_THRESHOLD 1.0
    fi
}


load_config
validate_config


# =========================
# Memory
# =========================

get_psi_usage() {
    local some_avg10
    local full_avg10

    PSI_AVAILABLE=false
    PSI_SOME_AVG10=0
    PSI_FULL_AVG10=0

    [[ -r "$PSI_SOURCE" ]] || return 0

    some_avg10=$(awk '/^some / {for (field = 1; field <= NF; field++) if ($field ~ /^avg10=/) {sub(/^avg10=/, "", $field); print $field; exit}}' "$PSI_SOURCE")
    full_avg10=$(awk '/^full / {for (field = 1; field <= NF; field++) if ($field ~ /^avg10=/) {sub(/^avg10=/, "", $field); print $field; exit}}' "$PSI_SOURCE")

    if is_percentage "$some_avg10"; then
        PSI_SOME_AVG10="$some_avg10"
        if is_percentage "$full_avg10"; then
            PSI_FULL_AVG10="$full_avg10"
        fi
        PSI_AVAILABLE=true
    fi
}


psi_at_or_above() {
    awk -v value="$1" -v threshold="$2" \
        'BEGIN { exit !(value >= threshold) }'
}


psi_has_reset() {
    [[ "$PSI_AVAILABLE" == false ]] ||
        ! psi_at_or_above "$PSI_SOME_AVG10" "$PSI_SOME_RESET_THRESHOLD"
}

get_memory_usage() {
    MEM_TOTAL=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    MEM_AVAILABLE=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)

    SWAP_TOTAL=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
    SWAP_FREE=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo)

    MEM_USED=$((MEM_TOTAL - MEM_AVAILABLE))
    MEM_USED_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))

    if (( SWAP_TOTAL > 0 )); then
        SWAP_USED=$((SWAP_TOTAL - SWAP_FREE))
        SWAP_USED_PERCENT=$((SWAP_USED * 100 / SWAP_TOTAL))
    else
        SWAP_USED=0
        SWAP_USED_PERCENT=0
    fi
}


# =========================
# Pressure state
# =========================

get_pressure_reason() {
    local ram_pressure=false
    local swap_pressure=false
    local psi_pressure=false
    local -a pressure_reasons=()

    if (( MEM_USED_PERCENT >= WARNING_THRESHOLD )); then
        ram_pressure=true
    fi

    # Occupied swap can remain high after pressure has passed. Treat it as
    # actionable only while RAM is also elevated.
    if (( SWAP_TOTAL > 0 &&
          SWAP_USED_PERCENT >= SWAP_WARNING_THRESHOLD &&
          MEM_USED_PERCENT >= RESET_THRESHOLD )); then
        swap_pressure=true
    fi

    if [[ "$PSI_AVAILABLE" == true ]] &&
       psi_at_or_above "$PSI_SOME_AVG10" "$PSI_SOME_WARNING_THRESHOLD"; then
        psi_pressure=true
    fi

    if [[ "$ram_pressure" == true ]]; then
        pressure_reasons+=("RAM is ${MEM_USED_PERCENT}%")
    fi

    if [[ "$swap_pressure" == true ]]; then
        pressure_reasons+=("swap is ${SWAP_USED_PERCENT}%")
    fi

    if [[ "$psi_pressure" == true ]]; then
        pressure_reasons+=("PSI some10 is ${PSI_SOME_AVG10}%")
    fi

    if (( ${#pressure_reasons[@]} == 0 )); then
        ALERT_MESSAGE=""
        return 1
    fi

    ALERT_MESSAGE="${pressure_reasons[0]}"
    for reason in "${pressure_reasons[@]:1}"; do
        ALERT_MESSAGE+=", $reason"
    done
    ALERT_MESSAGE+="."
}


pressure_has_reset() {
    if (( MEM_USED_PERCENT < RESET_THRESHOLD )); then
        psi_has_reset
        return
    fi

    (( MEM_USED_PERCENT <= RESET_THRESHOLD &&
       (SWAP_TOTAL == 0 || SWAP_USED_PERCENT <= SWAP_RESET_THRESHOLD) )) ||
        return 1

    psi_has_reset
}


# =========================
# Notifications
# =========================

show_warning() {
    log_event "WARNING" "Pressure alert: $ALERT_MESSAGE"

    if ! notify-send \
        -u critical \
        "MemWatch" \
        "$ALERT_MESSAGE"; then
        log_event "ERROR" "Failed to send the pressure notification."
    fi
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

get_process_identity() {
    local pid="$1"
    local executable_path
    local executable_name
    local script_argument
    local script_path
    local working_directory
    local -a command_line=()

    executable_path=$(readlink -f "/proc/$pid/exe" 2>/dev/null) || return 1
    executable_name="${executable_path##*/}"

    PROCESS_IDENTITY="$executable_path"
    PROCESS_NAME="$executable_name"

    case "$executable_name" in
        bash|dash|sh|zsh|python|python[0-9]*|node|perl|ruby)
            mapfile -d '' -t command_line < "/proc/$pid/cmdline" 2>/dev/null || return 0

            if (( ${#command_line[@]} > 1 )) &&
               [[ -n "${command_line[1]}" && "${command_line[1]}" != -* ]]; then
                script_argument="${command_line[1]}"

                if [[ "$script_argument" == /* ]]; then
                    script_path=$(readlink -f "$script_argument" 2>/dev/null)
                else
                    working_directory=$(readlink -f "/proc/$pid/cwd" 2>/dev/null)

                    if [[ -n "$working_directory" ]]; then
                        script_path=$(readlink -f "$working_directory/$script_argument" 2>/dev/null)
                    fi
                fi

                if [[ -n "$script_path" ]]; then
                    PROCESS_IDENTITY="$executable_path::$script_path"
                    PROCESS_NAME="${script_path##*/}"
                fi
            fi
            ;;
    esac
}


build_process_list() {
    local -A memory_by_identity=()
    local pid
    local rss
    local current_memory
    local identity
    local application_name

    PROCESS_ARGS=()
    APPLICATION_NAMES=()

    while read -r pid rss; do
        if ! get_process_identity "$pid"; then
            continue
        fi

        identity="$PROCESS_IDENTITY"
        application_name="$PROCESS_NAME"
        current_memory="${memory_by_identity["$identity"]:-0}"

        memory_by_identity["$identity"]=$((current_memory + rss))
        APPLICATION_NAMES["$identity"]="$application_name"
    done < <(ps -eo pid=,rss=)

    while IFS=$'\t' read -r rss application_name identity; do
        RAM=$(format_ram "$rss")

        PROCESS_ARGS+=(
            "$identity"
            "$application_name"
            "$RAM"
        )

    done < <(
        for identity in "${!memory_by_identity[@]}"; do
            printf '%s\t%s\t%s\n' \
                "${memory_by_identity["$identity"]}" \
                "${APPLICATION_NAMES["$identity"]}" \
                "$identity"
        done |
            sort -t $'\t' -k1,1nr |
            head -n "$PROCESS_LIMIT"
    )
}


# =========================
# Process picker
# =========================

show_process_picker() {
    if SELECTED_IDENTITY=$(zenity \
        --list \
        --title="MemWatch" \
        --text="$ALERT_MESSAGE

Select an application:" \
        --column="Identity" \
        --hide-column=1 \
        --print-column=1 \
        --column="Application" \
        --column="RAM" \
        --width=650 \
        --height=400 \
        "${PROCESS_ARGS[@]}"); then
        SELECTED_APPLICATION="${APPLICATION_NAMES["$SELECTED_IDENTITY"]:-${SELECTED_IDENTITY##*/}}"
        log_event "INFO" "Selected application: $SELECTED_APPLICATION ($SELECTED_IDENTITY)"
        return 0
    fi

    SELECTED_IDENTITY=""
    SELECTED_APPLICATION=""
    log_event "INFO" "Process picker dismissed without a selection."
    return 1
}


# =========================
# Process helpers
# =========================

process_exists() {
    local pid="$1"

    kill -0 "$pid" 2>/dev/null
}


get_process_pids() {
    local target_identity="$1"
    local process_directory
    local pid

    for process_directory in /proc/[0-9]*; do
        pid="${process_directory##*/}"

        if get_process_identity "$pid" &&
           [[ "$PROCESS_IDENTITY" == "$target_identity" ]]; then
            printf '%s\n' "$pid"
        fi
    done
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

        log_event "WARNING" "Sending SIGKILL to $process_name (PID $pid)."

        if ! kill -9 "$pid"; then
            log_event "ERROR" "Failed to send SIGKILL to $process_name (PID $pid)."
        fi

        sleep 1

        if process_exists "$pid"; then
            log_event "ERROR" "$process_name (PID $pid) remained after SIGKILL."
            notify-send \
                -u critical \
                "MemWatch" \
                "Failed to force close $process_name."
        else
            log_event "INFO" "$process_name (PID $pid) was force closed."
            notify-send \
                "MemWatch" \
                "$process_name was force closed."
        fi
    else
        log_event "INFO" "Force close canceled for $process_name (PID $pid)."
    fi
}


# =========================
# Close process
# =========================

close_process() {
    local pid="$1"

    # The process may have disappeared since the picker opened.
    if ! process_exists "$pid"; then
        log_event "INFO" "Selected PID $pid is no longer running."
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

        log_event "INFO" "Sending SIGTERM to $process_name (PID $pid)."

        if ! kill "$pid"; then
            log_event "ERROR" "Failed to send SIGTERM to $process_name (PID $pid)."
        fi

        # Give SIGTERM some time to work.
        sleep 2

        if process_exists "$pid"; then
            log_event "WARNING" "$process_name (PID $pid) remained after SIGTERM."
            force_close_process "$pid" "$process_name"
        else
            log_event "INFO" "$process_name (PID $pid) closed successfully."
            notify-send \
                "MemWatch" \
                "$process_name closed successfully."
        fi
    else
        log_event "INFO" "Close canceled for $process_name (PID $pid)."
    fi
}


# =========================
# Close process group
# =========================

close_process_group() {
    local process_identity="$1"
    local process_name="$2"

    mapfile -t pids < <(get_process_pids "$process_identity")

    local process_count="${#pids[@]}"

    if (( process_count == 0 )); then
        log_event "INFO" "$process_name is no longer running."
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

        log_event "INFO" "Sending SIGTERM to $process_count $process_name process(es): ${pids[*]}"
        if ! kill "${pids[@]}" 2>/dev/null; then
            log_event "ERROR" "SIGTERM could not be sent to every $process_name process."
        fi

        sleep 2

        mapfile -t remaining_pids < <(get_process_pids "$process_identity")

        if (( ${#remaining_pids[@]} == 0 )); then
            log_event "INFO" "$process_name closed successfully."
            notify-send \
                "MemWatch" \
                "$process_name closed successfully."

        else
            log_event "WARNING" "$process_name still has ${#remaining_pids[@]} process(es) after SIGTERM: ${remaining_pids[*]}"

            if zenity \
                --question \
                --title="MemWatch" \
                --text="$process_name still has ${#remaining_pids[@]} process(es) running.

Do you want to force close the remaining processes?" \
                --ok-label="Force Close Remaining" \
                --cancel-label="Leave Running"; then

                log_event "WARNING" "Sending SIGKILL to remaining $process_name process(es): ${remaining_pids[*]}"
                if ! kill -9 "${remaining_pids[@]}" 2>/dev/null; then
                    log_event "ERROR" "SIGKILL could not be sent to every remaining $process_name process."
                fi

                sleep 1

                mapfile -t final_pids < <(get_process_pids "$process_identity")

                if (( ${#final_pids[@]} == 0 )); then
                    log_event "INFO" "$process_name was force closed."
                    notify-send \
                        "MemWatch" \
                        "$process_name was force closed."
                else
                    log_event "ERROR" "Failed to close ${#final_pids[@]} $process_name process(es): ${final_pids[*]}"
                    notify-send \
                        -u critical \
                        "MemWatch" \
                        "Failed to close ${#final_pids[@]} $process_name process(es)."
                fi
            else
                log_event "INFO" "Force close canceled for $process_name."
            fi
        fi
    else
        log_event "INFO" "Close canceled for $process_name."
    fi
}


# =========================
# High-memory handler
# =========================

handle_high_memory() {
    show_warning

    build_process_list

    if ! show_process_picker; then
        return
    fi

    close_process_group "$SELECTED_IDENTITY" "$SELECTED_APPLICATION"
}


# =========================
# Main loop
# =========================

main() {
    while true; do
        get_memory_usage
        get_psi_usage

        if [[ "$PSI_AVAILABLE" == true ]]; then
            psi_status="some10:${PSI_SOME_AVG10}% full10:${PSI_FULL_AVG10}%"
        else
            psi_status="unavailable"
        fi

        log_event "INFO" "Memory status: RAM=${MEM_USED_PERCENT}% Swap=${SWAP_USED_PERCENT}% PSI=${psi_status}"

        if get_pressure_reason; then
            if [[ "$WARNING_SENT" == false ]]; then
                WARNING_SENT=true

                handle_high_memory
            fi
        elif pressure_has_reset && [[ "$WARNING_SENT" == true ]]; then
            WARNING_SENT=false
            log_event "INFO" "Pressure alert re-armed."
        fi

        sleep "$CHECK_INTERVAL"
    done
}


if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main
fi
