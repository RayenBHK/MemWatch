#!/usr/bin/env bash

set -uo pipefail

TEST_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEMP_ROOT=$(mktemp -d)
FIXTURE_SCRIPT="$TEMP_ROOT/memwatch-test-script.sh"

cleanup() {
    if [[ -n "${NATIVE_PID:-}" ]]; then
        kill "$NATIVE_PID" 2>/dev/null || true
        wait "$NATIVE_PID" 2>/dev/null || true
    fi

    if [[ -n "${FIXTURE_PID:-}" ]]; then
        kill "$FIXTURE_PID" 2>/dev/null || true
        wait "$FIXTURE_PID" 2>/dev/null || true
    fi

    rm -rf "$TEMP_ROOT"
}

trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

assert_equal() {
    local expected="$1"
    local actual="$2"
    local description="$3"

    if [[ "$expected" != "$actual" ]]; then
        fail "$description (expected '$expected', got '$actual')"
    fi

    pass
}

assert_true() {
    local description="$1"
    shift

    if ! "$@"; then
        fail "$description"
    fi

    pass
}

assert_false() {
    local description="$1"
    shift

    if "$@"; then
        fail "$description"
    fi

    pass
}

TESTS_PASSED=0

export XDG_CONFIG_HOME="$TEMP_ROOT/config"
mkdir -p "$XDG_CONFIG_HOME"
mkdir -p "$XDG_CONFIG_HOME/memwatch"
printf '%s\n' \
    'WARNING_THRESHOLD=120' \
    'RESET_THRESHOLD=200' \
    'SWAP_WARNING_THRESHOLD=95' \
    'SWAP_RESET_THRESHOLD=100' \
    'PSI_SOME_WARNING_THRESHOLD=invalid' \
    'PSI_SOME_RESET_THRESHOLD=20.0' \
    'CHECK_INTERVAL=0' \
    'PROCESS_LIMIT=-2' \
    'UNKNOWN_SETTING=ignored' \
    > "$XDG_CONFIG_HOME/memwatch/config"

source "$TEST_ROOT/memwatch.sh" >/dev/null

assert_equal 85 "$WARNING_THRESHOLD" "invalid RAM warning uses the default"
assert_equal 80 "$RESET_THRESHOLD" "invalid RAM reset uses the default"
assert_equal 95 "$SWAP_WARNING_THRESHOLD" "valid swap warning is retained"
assert_equal 80 "$SWAP_RESET_THRESHOLD" "invalid swap reset uses the default"
assert_equal 10.0 "$PSI_SOME_WARNING_THRESHOLD" "invalid PSI warning uses the default"
assert_equal 1.0 "$PSI_SOME_RESET_THRESHOLD" "invalid PSI reset uses the default"
assert_equal 5 "$CHECK_INTERVAL" "invalid check interval uses the default"
assert_equal 10 "$PROCESS_LIMIT" "invalid process limit uses the default"

assert_true "production script passes bash syntax check" bash -n "$TEST_ROOT/memwatch.sh"
assert_equal "0 MiB" "$(format_ram 0)" "zero KiB formats as zero MiB"
assert_equal "1 MiB" "$(format_ram 1024)" "1024 KiB formats as one MiB"
assert_equal "1.0 GiB" "$(format_ram 1048576)" "1048576 KiB formats as one GiB"

get_memory_usage
(( MEM_TOTAL > 0 )) || fail "MemTotal should be positive"
(( MEM_AVAILABLE >= 0 )) || fail "MemAvailable should not be negative"
(( MEM_USED >= 0 )) || fail "calculated RAM usage should not be negative"
(( MEM_USED_PERCENT >= 0 && MEM_USED_PERCENT <= 100 )) || fail "RAM percentage should be between 0 and 100"
(( SWAP_USED_PERCENT >= 0 && SWAP_USED_PERCENT <= 100 )) || fail "swap percentage should be between 0 and 100"
pass

awk() {
    case "$1" in
        *MemTotal*) printf '1000\n' ;;
        *MemAvailable*) printf '400\n' ;;
        *SwapTotal*) printf '0\n' ;;
        *SwapFree*) printf '0\n' ;;
    esac
}

get_memory_usage
unset -f awk
assert_equal 0 "$SWAP_USED" "no-swap systems report zero swap usage"
assert_equal 0 "$SWAP_USED_PERCENT" "no-swap systems report zero swap percentage"

set_pressure() {
    MEM_USED_PERCENT="$1"
    SWAP_USED_PERCENT="$2"
    SWAP_TOTAL="$3"
}

PSI_SOURCE="$TEMP_ROOT/psi-memory"
printf '%s\n' \
    'some avg10=0.00 avg60=0.00 avg300=0.00 total=100' \
    'full avg10=0.00 avg60=0.00 avg300=0.00 total=20' \
    > "$PSI_SOURCE"
get_psi_usage
assert_equal true "$PSI_AVAILABLE" "PSI fixture is detected"
assert_equal 0.00 "$PSI_SOME_AVG10" "PSI some avg10 is parsed"
assert_equal 0.00 "$PSI_FULL_AVG10" "PSI full avg10 is parsed"

printf '%s\n' \
    'some avg10=12.50 avg60=5.00 avg300=1.00 total=100' \
    'full avg10=2.00 avg60=1.00 avg300=0.50 total=20' \
    > "$PSI_SOURCE"
get_psi_usage
set_pressure 70 0 0
assert_true "PSI pressure triggers an alert" get_pressure_reason
assert_equal "PSI some10 is 12.50%." "$ALERT_MESSAGE" "PSI alert message"

printf '%s\n' \
    'some avg10=0.50 avg60=0.20 avg300=0.10 total=100' \
    'full avg10=0.00 avg60=0.00 avg300=0.00 total=20' \
    > "$PSI_SOURCE"
get_psi_usage

set_pressure 84 0 0
assert_false "pressure stays quiet below the RAM threshold" get_pressure_reason

set_pressure 85 0 0
assert_true "RAM threshold triggers pressure" get_pressure_reason
assert_equal "RAM is 85%." "$ALERT_MESSAGE" "RAM alert message"

set_pressure 82 95 1000
assert_true "high swap with elevated RAM triggers pressure" get_pressure_reason
assert_equal "swap is 95%." "$ALERT_MESSAGE" "swap alert message"

set_pressure 85 95 1000
assert_true "RAM and swap pressure produce a combined alert" get_pressure_reason
assert_equal "RAM is 85%, swap is 95%." "$ALERT_MESSAGE" "combined alert message"

set_pressure 79 100 1000
assert_false "high swap with low RAM stays quiet" get_pressure_reason

printf '%s\n' \
    'some avg10=12.50 avg60=5.00 avg300=1.00 total=100' \
    'full avg10=2.00 avg60=1.00 avg300=0.50 total=20' \
    > "$PSI_SOURCE"
get_psi_usage
set_pressure 79 0 0
assert_false "high PSI with low RAM stays armed" pressure_has_reset

printf '%s\n' \
    'some avg10=0.50 avg60=0.20 avg300=0.10 total=100' \
    'full avg10=0.00 avg60=0.00 avg300=0.00 total=20' \
    > "$PSI_SOURCE"
get_psi_usage
set_pressure 79 100 1000
assert_true "RAM below reset threshold re-arms alerts" pressure_has_reset

set_pressure 80 85 1000
assert_false "reset threshold with high swap stays armed" pressure_has_reset

set_pressure 80 80 1000
assert_true "reset threshold with low swap re-arms alerts" pressure_has_reset

set_pressure 80 0 0
assert_true "systems without swap can re-arm alerts" pressure_has_reset

PSI_SOURCE="$TEMP_ROOT/missing-psi"
get_psi_usage
assert_equal false "$PSI_AVAILABLE" "missing PSI remains optional"

log_output=$(log_event INFO "Test event")
assert_equal "MemWatch [INFO] Test event" "$log_output" "structured log output"

sleep 30 &
NATIVE_PID=$!
get_process_identity "$NATIVE_PID" || fail "native fixture identity should resolve"
current_identity="$PROCESS_IDENTITY"
expected_identity=$(readlink -f "/proc/$NATIVE_PID/exe")
assert_equal "$expected_identity" "$current_identity" "native process identity"

printf '#!/usr/bin/env bash\nsleep 30\n' > "$FIXTURE_SCRIPT"
bash "$FIXTURE_SCRIPT" &
FIXTURE_PID=$!
sleep 0.1

get_process_identity "$FIXTURE_PID" || fail "fixture script identity should resolve"
script_interpreter_path=$(readlink -f "/proc/$FIXTURE_PID/exe")
assert_equal "${script_interpreter_path}::$FIXTURE_SCRIPT" "$PROCESS_IDENTITY" "interpreted script identity"
assert_equal "${FIXTURE_SCRIPT##*/}" "$PROCESS_NAME" "interpreted script display name"

build_process_list
(( ${#PROCESS_ARGS[@]} > 0 )) || fail "process list should contain at least one group"
(( ${#PROCESS_ARGS[@]} % 3 == 0 )) || fail "process list should contain identity/name/RAM triplets"
(( ${#PROCESS_ARGS[@]} <= PROCESS_LIMIT * 3 )) || fail "process list should honor PROCESS_LIMIT"
pass

mapfile -t matching_pids < <(get_process_pids "$current_identity")
matched_current_pid=false
for pid in "${matching_pids[@]}"; do
    if [[ "$pid" == "$NATIVE_PID" ]]; then
        matched_current_pid=true
        break
    fi
done

assert_equal true "$matched_current_pid" "identity lookup should return the native fixture PID"

INSTALL_HOME="$TEMP_ROOT/install-home"
INSTALL_CONFIG="$TEMP_ROOT/install-config"
FAKE_BIN="$TEMP_ROOT/fake-bin"
mkdir -p "$FAKE_BIN"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "${2:-}" == is-active || "${2:-}" == is-enabled ]]; then exit 1; fi' \
    'exit 0' \
    > "$FAKE_BIN/systemctl"
chmod +x "$FAKE_BIN/systemctl"

HOME="$INSTALL_HOME" \
XDG_CONFIG_HOME="$INSTALL_CONFIG" \
PATH="$FAKE_BIN:$PATH" \
    "$TEST_ROOT/install.sh" >/dev/null || fail "isolated installer should succeed"

[[ -x "$INSTALL_HOME/.local/share/memwatch/memwatch.sh" ]] ||
    fail "installer should install an executable monitor"

[[ -f "$INSTALL_CONFIG/systemd/user/memwatch.service" ]] ||
    fail "installer should install the user service"

grep -Fx 'ExecStart=%h/.local/share/memwatch/memwatch.sh' \
    "$INSTALL_CONFIG/systemd/user/memwatch.service" >/dev/null ||
    fail "installed service should use the stable user-local path"

printf 'CUSTOM=preserved\n' >> "$INSTALL_CONFIG/memwatch/config"

HOME="$INSTALL_HOME" \
XDG_CONFIG_HOME="$INSTALL_CONFIG" \
PATH="$FAKE_BIN:$PATH" \
    "$TEST_ROOT/install.sh" >/dev/null || fail "reinstall should succeed"

grep -Fx 'CUSTOM=preserved' "$INSTALL_CONFIG/memwatch/config" >/dev/null ||
    fail "reinstall should preserve the personal configuration"

HOME="$INSTALL_HOME" \
XDG_CONFIG_HOME="$INSTALL_CONFIG" \
PATH="$FAKE_BIN:$PATH" \
    "$TEST_ROOT/uninstall.sh" >/dev/null || fail "uninstall should succeed"

[[ ! -e "$INSTALL_HOME/.local/share/memwatch/memwatch.sh" ]] ||
    fail "uninstall should remove the installed monitor"

[[ ! -e "$INSTALL_CONFIG/systemd/user/memwatch.service" ]] ||
    fail "uninstall should remove the installed service"

[[ -f "$INSTALL_CONFIG/memwatch/config" ]] ||
    fail "normal uninstall should preserve the personal configuration"

HOME="$INSTALL_HOME" \
XDG_CONFIG_HOME="$INSTALL_CONFIG" \
PATH="$FAKE_BIN:$PATH" \
    "$TEST_ROOT/install.sh" >/dev/null || fail "reinstall before purge should succeed"

HOME="$INSTALL_HOME" \
XDG_CONFIG_HOME="$INSTALL_CONFIG" \
PATH="$FAKE_BIN:$PATH" \
    "$TEST_ROOT/uninstall.sh" --purge >/dev/null || fail "purge uninstall should succeed"

[[ ! -e "$INSTALL_CONFIG/memwatch/config" ]] ||
    fail "purge uninstall should remove the personal configuration"
pass

printf 'PASS: %d checks completed.\n' "$TESTS_PASSED"
