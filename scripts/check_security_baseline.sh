#!/usr/bin/env bash
# ==============================================================================
# Script: check_security_baseline.sh
# Purpose: Comprehensive security compliance rollup plugin for Nagios & NRPE.
# Evaluates:
#   1. Puppet Agent execution & convergence daemon status
#   2. SSH daemon hardening baseline
#   3. Mandatory security services (auditd, ufw, timesyncd)
#   4. Sensitive credential file modes and permissions
# Standards: Nagios Plugin API return codes (0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN)
# ==============================================================================

set -o pipefail

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

OVERALL_STATUS=$STATE_OK
SUMMARY_MSGS=()
DETAIL_MSGS=()

# ------------------------------------------------------------------------------
# 1. Audit Puppet Agent Daemon
# ------------------------------------------------------------------------------
if systemctl is-active --quiet puppet 2>/dev/null; then
    DETAIL_MSGS+=("Puppet Agent: ACTIVE")
else
    OVERALL_STATUS=$STATE_CRITICAL
    SUMMARY_MSGS+=("Puppet Agent is INACTIVE")
    DETAIL_MSGS+=("Puppet Agent: INACTIVE (Automatic remediation disabled)")
fi

# ------------------------------------------------------------------------------
# 2. Audit SSH Security Parameters
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -x "${SCRIPT_DIR}/check_ssh_security.sh" ]]; then
    SSH_OUTPUT=$("${SCRIPT_DIR}/check_ssh_security.sh")
    SSH_EXIT=$?
    if [[ $SSH_EXIT -eq $STATE_CRITICAL ]]; then
        [[ $OVERALL_STATUS -lt $STATE_CRITICAL ]] && OVERALL_STATUS=$STATE_CRITICAL
        SUMMARY_MSGS+=("SSH Hardening DRIFT")
        DETAIL_MSGS+=("SSH Check: $SSH_OUTPUT")
    elif [[ $SSH_EXIT -eq $STATE_WARNING ]]; then
        [[ $OVERALL_STATUS -lt $STATE_WARNING ]] && OVERALL_STATUS=$STATE_WARNING
        SUMMARY_MSGS+=("SSH Hardening WARNING")
        DETAIL_MSGS+=("SSH Check: $SSH_OUTPUT")
    else
        DETAIL_MSGS+=("SSH Check: COMPLIANT")
    fi
else
    # Fallback inline check if companion script not in same path
    ROOT_VAL=$(grep -iE "^\s*PermitRootLogin\b" /etc/ssh/sshd_config 2>/dev/null | tail -n 1 | awk '{print $2}')
    if [[ "${ROOT_VAL,,}" == "yes" ]]; then
        OVERALL_STATUS=$STATE_CRITICAL
        SUMMARY_MSGS+=("PermitRootLogin=yes")
        DETAIL_MSGS+=("SSH: PermitRootLogin is 'yes' (CRITICAL)")
    else
        DETAIL_MSGS+=("SSH: PermitRootLogin=${ROOT_VAL:-no}")
    fi
fi

# ------------------------------------------------------------------------------
# 3. Audit Mandatory Security Services
# ------------------------------------------------------------------------------
if [[ -x "${SCRIPT_DIR}/check_services.sh" ]]; then
    SVC_OUTPUT=$("${SCRIPT_DIR}/check_services.sh")
    SVC_EXIT=$?
    if [[ $SVC_EXIT -eq $STATE_CRITICAL ]]; then
        [[ $OVERALL_STATUS -lt $STATE_CRITICAL ]] && OVERALL_STATUS=$STATE_CRITICAL
        SUMMARY_MSGS+=("Security Services INACTIVE")
        DETAIL_MSGS+=("Services Check: $SVC_OUTPUT")
    else
        DETAIL_MSGS+=("Security Services: ACTIVE")
    fi
else
    for s in auditd ufw systemd-timesyncd; do
        if ! systemctl is-active --quiet "$s" 2>/dev/null; then
            OVERALL_STATUS=$STATE_CRITICAL
            SUMMARY_MSGS+=("Service '$s' stopped")
            DETAIL_MSGS+=("Service '$s': STOPPED")
        fi
    done
fi

# ------------------------------------------------------------------------------
# 4. Audit Critical File Permissions
# ------------------------------------------------------------------------------
if [[ -x "${SCRIPT_DIR}/check_file_permissions.sh" ]]; then
    PERM_OUTPUT=$("${SCRIPT_DIR}/check_file_permissions.sh")
    PERM_EXIT=$?
    if [[ $PERM_EXIT -eq $STATE_CRITICAL ]]; then
        [[ $OVERALL_STATUS -lt $STATE_CRITICAL ]] && OVERALL_STATUS=$STATE_CRITICAL
        SUMMARY_MSGS+=("File Permissions DRIFT")
        DETAIL_MSGS+=("Permissions Check: $PERM_OUTPUT")
    elif [[ $PERM_EXIT -eq $STATE_WARNING ]]; then
        [[ $OVERALL_STATUS -lt $STATE_WARNING ]] && OVERALL_STATUS=$STATE_WARNING
        SUMMARY_MSGS+=("File Permissions WARNING")
        DETAIL_MSGS+=("Permissions Check: $PERM_OUTPUT")
    else
        DETAIL_MSGS+=("File Permissions: SECURE")
    fi
fi

# ------------------------------------------------------------------------------
# Format and Output Results
# ------------------------------------------------------------------------------
if [[ $OVERALL_STATUS -eq $STATE_CRITICAL ]]; then
    echo "CRITICAL - Security Baseline Drift Detected: ${SUMMARY_MSGS[*]}"
    printf ' - %s\n' "${DETAIL_MSGS[@]}"
    exit $STATE_CRITICAL
elif [[ $OVERALL_STATUS -eq $STATE_WARNING ]]; then
    echo "WARNING - Security Baseline Deviations: ${SUMMARY_MSGS[*]}"
    printf ' - %s\n' "${DETAIL_MSGS[@]}"
    exit $STATE_WARNING
else
    echo "OK - Complete security baseline is compliant across SSH, daemons, permissions, and Puppet Agent."
    printf ' - %s\n' "${DETAIL_MSGS[@]}"
    exit $STATE_OK
fi

