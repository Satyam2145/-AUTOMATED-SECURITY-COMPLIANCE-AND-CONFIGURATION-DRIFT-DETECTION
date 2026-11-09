#!/usr/bin/env bash
# ==============================================================================
# Script: simulate_drift.sh
# Purpose: Interactive/CLI test utility to inject controlled configuration
#          drift, execute compliance audits, and trigger Puppet remediation.
# Standards: Academic & Capstone Demonstration Utility
# ==============================================================================

set -uo pipefail

RED='\033[0;32;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR] This operation requires root privileges. Please run with sudo.${NC}"
        exit 1
    fi
}

inject_ssh_drift() {
    check_root
    echo -e "${YELLOW}[DRIFT] Injecting SSH Configuration Drift...${NC}"
    if grep -q "PermitRootLogin" /etc/ssh/sshd_config; then
        sed -i 's/^.*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    else
        echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
    fi
    systemctl reload ssh || systemctl restart ssh
    echo -e "${RED}[DRIFT INJECTED] /etc/ssh/sshd_config modified: PermitRootLogin=yes (UNAUTHORIZED)${NC}"
}

inject_service_drift() {
    check_root
    echo -e "${YELLOW}[DRIFT] Injecting Security Daemon Drift...${NC}"
    systemctl stop auditd 2>/dev/null || systemctl stop systemd-timesyncd 2>/dev/null || true
    echo -e "${RED}[DRIFT INJECTED] Required security service stopped!${NC}"
}

inject_perms_drift() {
    check_root
    echo -e "${YELLOW}[DRIFT] Injecting File Permissions Drift...${NC}"
    chmod 666 /etc/shadow
    echo -e "${RED}[DRIFT INJECTED] /etc/shadow mode altered to 0666 (WORLD-WRITABLE)${NC}"
}

inject_all() {
    inject_ssh_drift
    inject_service_drift
    inject_perms_drift
}

run_audit() {
    echo -e "\n${CYAN}================================================================${NC}"
    echo -e "${CYAN}             Live Security Compliance Audit Probes             ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    
    echo -e "\n--- [1] SSH Security Hardening Probe ---"
    if [[ -x "$SCRIPT_DIR/check_ssh_security.sh" ]]; then
        "$SCRIPT_DIR/check_ssh_security.sh" || true
    else
        echo "Script not found: $SCRIPT_DIR/check_ssh_security.sh"
    fi

    echo -e "\n--- [2] Essential Daemons Probe ---"
    if [[ -x "$SCRIPT_DIR/check_services.sh" ]]; then
        "$SCRIPT_DIR/check_services.sh" || true
    else
        echo "Script not found: $SCRIPT_DIR/check_services.sh"
    fi

    echo -e "\n--- [3] Critical File Permissions Probe ---"
    if [[ -x "$SCRIPT_DIR/check_file_permissions.sh" ]]; then
        "$SCRIPT_DIR/check_file_permissions.sh" || true
    else
        echo "Script not found: $SCRIPT_DIR/check_file_permissions.sh"
    fi

    echo -e "\n--- [4] Overall Security Baseline Rollup ---"
    if [[ -x "$SCRIPT_DIR/check_security_baseline.sh" ]]; then
        "$SCRIPT_DIR/check_security_baseline.sh" || true
    else
        echo "Script not found: $SCRIPT_DIR/check_security_baseline.sh"
    fi
    echo -e "${CYAN}================================================================${NC}\n"
}

remediate_puppet() {
    check_root
    echo -e "\n${GREEN}[REMEDIATION] Triggering Puppet Declarative Convergence...${NC}"
    if command -v puppet &>/dev/null; then
        puppet agent -t || true
    elif [[ -x "/opt/puppetlabs/bin/puppet" ]]; then
        /opt/puppetlabs/bin/puppet agent -t || true
    else
        echo -e "${RED}[ERROR] Puppet Agent binary not found in PATH or /opt/puppetlabs/bin!${NC}"
        exit 1
    fi
    echo -e "${GREEN}[REMEDIATION COMPLETE] Puppet catalog converged to authoritative baseline.${NC}\n"
}

show_usage() {
    echo "Usage: sudo $0 [OPTION]"
    echo "Options:"
    echo "  --inject-ssh      Introduce unauthorized SSH root login drift (PermitRootLogin yes)"
    echo "  --inject-service  Stop mandatory security daemon (auditd / timesyncd)"
    echo "  --inject-perms    Tamper with /etc/shadow permissions (0666)"
    echo "  --inject-all      Introduce all three drift vectors simultaneously"
    echo "  --status          Run live Nagios compliance check probes"
    echo "  --remediate       Trigger Puppet Agent convergence to recover baseline"
    echo "  --help            Display this help dialog"
}

# Main Execution Routing
case "${1:-menu}" in
    --inject-ssh)
        inject_ssh_drift
        ;;
    --inject-service)
        inject_service_drift
        ;;
    --inject-perms)
        inject_perms_drift
        ;;
    --inject-all)
        inject_all
        ;;
    --status)
        run_audit
        ;;
    --remediate)
        remediate_puppet
        run_audit
        ;;
    --help)
        show_usage
        ;;
    menu)
        while true; do
            echo -e "\n${CYAN}================================================================${NC}"
            echo -e "${CYAN}    DevOps Drift Detection & Remediation Lab Control Center    ${NC}"
            echo -e "${CYAN}================================================================${NC}"
            echo " 1) Run Live Security Compliance Audit (--status)"
            echo " 2) Inject SSH Root Login Drift (PermitRootLogin yes)"
            echo " 3) Inject Security Service Drift (Stop auditd)"
            echo " 4) Inject File Permission Drift (chmod 666 /etc/shadow)"
            echo " 5) Inject ALL Drift Vectors Simultaneously"
            echo " 6) Trigger Puppet Remediation Convergence (--remediate)"
            echo " 7) Exit"
            echo -e "${CYAN}================================================================${NC}"
            read -rp "Select an option [1-7]: " choice
            case "$choice" in
                1) run_audit ;;
                2) inject_ssh_drift; run_audit ;;
                3) inject_service_drift; run_audit ;;
                4) inject_perms_drift; run_audit ;;
                5) inject_all; run_audit ;;
                6) remediate_puppet; run_audit ;;
                7) exit 0 ;;
                *) echo "Invalid choice." ;;
            esac
        done
        ;;
    *)
        show_usage
        exit 1
        ;;
esac

