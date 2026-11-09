#!/usr/bin/env bash
# ==============================================================================
# Script: check_services.sh
# Purpose: Nagios compliance plugin to detect security daemon drift.
# Standards: Nagios Plugin API return codes (0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN)
# ==============================================================================

set -o pipefail

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

REQUIRED_SERVICES=("auditd" "ufw" "systemd-timesyncd")
INSECURE_SERVICES=("telnet" "rsh" "xinetd" "nis")

ERRORS=()
WARNINGS=()
CHECKED_SERVICES=0

# Check required services
for svc in "${REQUIRED_SERVICES[@]}"; do
    ((CHECKED_SERVICES++))
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        : # Service is running as expected
    else
        # Determine if service is failed or simply stopped
        STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
        ENABLED=$(systemctl is-enabled "$svc" 2>/dev/null || echo "disabled")
        ERRORS+=("Required service '$svc' is $STATUS (enabled: $ENABLED)")
    fi
done

# Check forbidden insecure services
for bad_svc in "${INSECURE_SERVICES[@]}"; do
    if systemctl is-active --quiet "$bad_svc" 2>/dev/null; then
        ERRORS+=("Insecure service '$bad_svc' is running!")
    fi
done

# Evaluate state and print Nagios formatted output
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo "CRITICAL - Security Service Drift Detected: ${ERRORS[*]} | required_active=$((CHECKED_SERVICES - ${#ERRORS[@]})) failed=${#ERRORS[@]}"
    exit $STATE_CRITICAL
elif [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo "WARNING - Security Service Anomaly: ${WARNINGS[*]}"
    exit $STATE_WARNING
else
    echo "OK - All mandatory security services (auditd, ufw, timesyncd) are active and running | required_active=${CHECKED_SERVICES} failed=0"
    exit $STATE_OK
fi

