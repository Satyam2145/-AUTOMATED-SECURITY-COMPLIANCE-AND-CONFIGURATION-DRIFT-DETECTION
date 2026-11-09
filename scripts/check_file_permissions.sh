#!/usr/bin/env bash
# ==============================================================================
# Script: check_file_permissions.sh
# Purpose: Nagios compliance plugin to detect file permission and ownership drift.
# Standards: Nagios Plugin API return codes (0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN)
# ==============================================================================

set -o pipefail

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

ERRORS=()
WARNINGS=()

# Helper function to audit a file
# Arguments: path, expected_max_mode, expected_owner, expected_group
audit_file() {
    local file="$1"
    local max_mode="$2"
    local expected_owner="$3"
    local expected_group="$4"

    if [[ ! -e "$file" ]]; then
        ERRORS+=("Critical file '$file' is missing")
        return
    fi

    local current_mode
    local current_owner
    local current_group

    current_mode=$(stat -c "%a" "$file" 2>/dev/null)
    current_owner=$(stat -c "%U" "$file" 2>/dev/null)
    current_group=$(stat -c "%G" "$file" 2>/dev/null)

    # Check owner
    if [[ "$current_owner" != "$expected_owner" ]]; then
        ERRORS+=("$file owner is '$current_owner' (expected '$expected_owner')")
    fi

    # Check group
    if [[ -n "$expected_group" && "$current_group" != "$expected_group" ]]; then
        WARNINGS+=("$file group is '$current_group' (expected '$expected_group')")
    fi

    # Check world-writable flag (bit 2 on other: 2, 3, 6, 7)
    if [[ "$current_mode" =~ ..[2367] ]]; then
        ERRORS+=("$file is WORLD-WRITABLE (mode: $current_mode)!")
    fi

    # Special check for /etc/shadow or /etc/gshadow (Must NOT be readable by others)
    if [[ "$file" == "/etc/shadow" || "$file" == "/etc/gshadow" ]]; then
        if [[ "$current_mode" =~ ..[1-7] ]]; then
            ERRORS+=("$file is WORLD-READABLE or ACCESSIBLE (mode: $current_mode)!")
        fi
    fi

    # Check mode bounds
    if [[ "$current_mode" -gt "$max_mode" ]]; then
        WARNINGS+=("$file mode is $current_mode (expected <= $max_mode)")
    fi
}

# Audit sensitive files
audit_file "/etc/shadow" 640 "root" "shadow"
audit_file "/etc/gshadow" 640 "root" "shadow"
audit_file "/etc/passwd" 644 "root" "root"
audit_file "/etc/group" 644 "root" "root"
audit_file "/etc/crontab" 600 "root" "root"
audit_file "/etc/ssh/sshd_config" 600 "root" "root"

# Evaluate state and print Nagios formatted output
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo "CRITICAL - File Permission Drift Detected: ${ERRORS[*]} | violations=${#ERRORS[@]}"
    exit $STATE_CRITICAL
elif [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo "WARNING - File Permission Discrepancy: ${WARNINGS[*]} | warnings=${#WARNINGS[@]}"
    exit $STATE_WARNING
else
    echo "OK - All critical system files have secure permissions and ownership (/etc/shadow 0640, /etc/passwd 0644, /etc/ssh/sshd_config 0600) | violations=0"
    exit $STATE_OK
fi

