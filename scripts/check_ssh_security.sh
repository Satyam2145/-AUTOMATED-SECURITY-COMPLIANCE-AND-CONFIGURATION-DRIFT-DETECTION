#!/usr/bin/env bash
# ==============================================================================
# Script: check_ssh_security.sh
# Purpose: Nagios compliance plugin to detect SSH configuration drift.
# Standards: Nagios Plugin API return codes (0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN)
# ==============================================================================

set -o pipefail

# Return code constants
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

CONFIG_FILE="/etc/ssh/sshd_config"

# Check 1: Existence and readability of configuration file
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "UNKNOWN - SSH configuration file $CONFIG_FILE does not exist."
    exit $STATE_UNKNOWN
fi

if [[ ! -r "$CONFIG_FILE" ]]; then
    echo "UNKNOWN - Unable to read $CONFIG_FILE (permission denied)."
    exit $STATE_UNKNOWN
fi

# Function to parse effective SSH directive (case-insensitive, ignores commented lines)
get_sshd_param() {
    local param="$1"
    # First search sshd_config.d drop-in directory if present
    local val=""
    if [[ -d "/etc/ssh/sshd_config.d" ]]; then
        val=$(grep -rihE "^\s*${param}\b" /etc/ssh/sshd_config.d/ 2>/dev/null | tail -n 1 | awk '{print $2}')
    fi
    # If not found in drop-ins, check primary sshd_config
    if [[ -z "$val" ]]; then
        val=$(grep -iE "^\s*${param}\b" "$CONFIG_FILE" 2>/dev/null | tail -n 1 | awk '{print $2}')
    fi
    echo "$val"
}

# Extract critical security parameters
ROOT_LOGIN=$(get_sshd_param "PermitRootLogin")
PASSWORD_AUTH=$(get_sshd_param "PasswordAuthentication")
MAX_AUTH_TRIES=$(get_sshd_param "MaxAuthTries")

# Fallback defaults if unspecified in config (OpenSSH defaults)
[[ -z "$ROOT_LOGIN" ]] && ROOT_LOGIN="prohibit-password"
[[ -z "$PASSWORD_AUTH" ]] && PASSWORD_AUTH="yes"

ERRORS=()
WARNINGS=()

# Check 2: PermitRootLogin Baseline (Approved baseline: 'no')
if [[ "${ROOT_LOGIN,,}" == "yes" ]]; then
    ERRORS+=("PermitRootLogin is set to '${ROOT_LOGIN}' (Policy requires 'no')")
elif [[ "${ROOT_LOGIN,,}" == "prohibit-password" ]] || [[ "${ROOT_LOGIN,,}" == "without-password" ]]; then
    WARNINGS+=("PermitRootLogin is '${ROOT_LOGIN}' (Policy recommends strict 'no')")
fi

# Check 3: PasswordAuthentication Baseline (Approved baseline: 'no')
if [[ "${PASSWORD_AUTH,,}" == "yes" ]]; then
    ERRORS+=("PasswordAuthentication is set to '${PASSWORD_AUTH}' (Policy requires 'no')")
fi

# Check 4: MaxAuthTries (Approved baseline: <= 4)
if [[ -n "$MAX_AUTH_TRIES" ]] && [[ "$MAX_AUTH_TRIES" -gt 4 ]]; then
    WARNINGS+=("MaxAuthTries is ${MAX_AUTH_TRIES} (Policy requires <= 4)")
fi

# Check 5: File permissions on sshd_config (Must not be world-writable or group-writable)
PERM=$(stat -c "%a" "$CONFIG_FILE" 2>/dev/null)
OWNER=$(stat -c "%U" "$CONFIG_FILE" 2>/dev/null)

if [[ "$PERM" =~ .[2367]. ]] || [[ "$PERM" =~ ..[2367] ]]; then
    ERRORS+=("File permissions on $CONFIG_FILE are too permissive ($PERM, owner: $OWNER)")
fi

# Evaluate state and print Nagios formatted output
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo "CRITICAL - SSH Configuration Drift Detected: ${ERRORS[*]} | permit_root_login=${ROOT_LOGIN} password_auth=${PASSWORD_AUTH}"
    exit $STATE_CRITICAL
elif [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo "WARNING - SSH Configuration Deviation: ${WARNINGS[*]} | permit_root_login=${ROOT_LOGIN} password_auth=${PASSWORD_AUTH}"
    exit $STATE_WARNING
else
    echo "OK - SSH configuration compliant with security baseline (PermitRootLogin=no, PasswordAuthentication=no) | permit_root_login=0 password_auth=0"
    exit $STATE_OK
fi

