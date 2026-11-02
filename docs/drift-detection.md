# Configuration Drift Detection & Automated Remediation Guide

**Project:** Automated Security Compliance and Configuration Drift Detection Using Puppet and Nagios on AWS EC2  
**Target Environment:** AWS EC2 (Ubuntu Linux LTS)  

---

## 1. Theoretical Foundation of Configuration Drift

**Configuration Drift** refers to the gradual degradation of consistency between a system's declared, authorized state and its live, runtime reality. In enterprise cloud deployments, drift typically occurs via:
1. **Ad-Hoc Troubleshooting (Out-of-Band Changes):** An engineer temporarily changes a setting (e.g., enabling `PermitRootLogin yes` or running `chmod 777` on a configuration file to bypass an access issue) and forgets to revert it.
2. **Unauthorized Tampering / Adversary Actions:** A compromised process or insider modifies daemon settings, disables security logging (`auditd`), or stops host firewalls (`ufw`).
3. **Uncoordinated Package Updates:** Automatic OS package upgrades that replace customized configurations with distribution defaults.

```
       +-------------------------------------------------------------+
       | Approved Golden Baseline (Puppet Manifest in Version Control)|
       +-------------------------------------------------------------+
                                      |
                         (Declarative Enforcement)
                                      v
       +-------------------------------------------------------------+
       |              Compliant Runtime State (EC2 Client)           |
       +-------------------------------------------------------------+
                                      |
                        (Manual Edit / Drift Event)
                                      v
       +-------------------------------------------------------------+
       |              DRIFTED NON-COMPLIANT STATE                     |
       +-------------------------------------------------------------+
                                      |
                         (Nagios NRPE Probe Detects)
                                      v
+---------------------------------------------------------------------------+
| Alert Generated in Nagios Dashboard within 120s (CRITICAL / Exit Code 2)  |
+---------------------------------------------------------------------------+
                                      |
                     (Puppet Remediation Triggered)
                                      v
+---------------------------------------------------------------------------+
| State Converged to Approved Baseline -> Nagios Returns to OK (Exit Code 0)|
+---------------------------------------------------------------------------+
```

---

## 2. Independent Detection Architecture

Relying solely on configuration management self-reporting introduces an operational blind spot:
- If Puppet Agent is stopped, disabled, or fails compilation, it cannot report drift.
- A declarative tool checks what it knows about; it does not actively monitor live file permissions or daemon statuses in real time.

This project implements **dual-control governance**:
- **Enforcement Engine:** Puppet Server & Agent (Declarative desired state).
- **Independent Auditor:** Nagios Core & NRPE (Deterministic compliance probing).

### Return Code Convention
All custom scripts in `scripts/` strictly enforce the official Nagios Plugin API specification:

| Return Code | Nagios State | Operational Meaning | Action Required |
| :---: | :---: | :--- | :--- |
| **0** | **OK** | System conforms exactly to approved security baseline. | None (Normal operation). |
| **1** | **WARNING** | Minor deviation or sub-optimal setting detected. | Investigate during business hours. |
| **2** | **CRITICAL** | Severe security baseline breach (e.g., root login enabled, shadow file exposed). | Immediate incident triage & remediation. |
| **3** | **UNKNOWN** | Script execution failure, missing files, or syntax error. | Verify monitoring configuration and file permissions. |

---

## 3. Hands-On Drift Scenarios & Demonstration

### Scenario A: Unauthorized SSH Root Login Drift

1. **Verify Baseline State:**  
   Check current status on Managed Client:
   ```bash
   /usr/local/lib/nagios/plugins/check_ssh_security.sh
   ```
   Expected output:
   ```text
   OK - SSH configuration compliant with security baseline (PermitRootLogin=no, PasswordAuthentication=no)
   ```

2. **Simulate Drift (Inject Unauthorized Change):**  
   Simulate an unauthorized modification allowing root login:
   ```bash
   sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
   sudo systemctl reload ssh
   ```

3. **Verify Immediate Local Detection:**  
   Execute the compliance check script:
   ```bash
   /usr/local/lib/nagios/plugins/check_ssh_security.sh
   echo "Exit Code: $?"
   ```
   Expected output:
   ```text
   CRITICAL - SSH Configuration Drift Detected: PermitRootLogin is set to 'yes' (Policy requires 'no') | permit_root_login=yes password_auth=no
   Exit Code: 2
   ```

4. **Observe Nagios Alert:**  
   Within 120 seconds, the Nagios Core web dashboard updates the service **`DRIFT: SSH Security Hardening`** to **`CRITICAL` (Red)** with alert details prominently displayed.

---

### Scenario B: Security Daemon Tampering (Disabling `auditd`)

1. **Simulate Drift (Stopping Security Service):**  
   An unauthorized user stops the Linux audit daemon:
   ```bash
   sudo systemctl stop auditd
   ```

2. **Verify Detection:**  
   Execute the services compliance check:
   ```bash
   /usr/local/lib/nagios/plugins/check_services.sh
   echo "Exit Code: $?"
   ```
   Expected output:
   ```text
   CRITICAL - Security Service Drift Detected: Required service 'auditd' is inactive (enabled: enabled) | required_active=2 failed=1
   Exit Code: 2
   ```

3. **Observe Nagios Alert:**  
   Nagios service **`DRIFT: Security Services Execution`** transitions to **`CRITICAL` (Red)**.

---

### Scenario C: Permission Tampering on Sensitive Files

1. **Simulate Drift (Compromising `/etc/shadow` Permissions):**  
   Accidental permission leak exposing the password hashes:
   ```bash
   sudo chmod 666 /etc/shadow
   ```

2. **Verify Detection:**  
   Execute the file permissions check:
   ```bash
   /usr/local/lib/nagios/plugins/check_file_permissions.sh
   echo "Exit Code: $?"
   ```
   Expected output:
   ```text
   CRITICAL - File Permission Drift Detected: /etc/shadow is WORLD-WRITABLE (mode: 666)! /etc/shadow is WORLD-READABLE or ACCESSIBLE (mode: 666)! | violations=2
   Exit Code: 2
   ```

3. **Observe Nagios Alert:**  
   Nagios service **`DRIFT: Critical File Permissions`** transitions to **`CRITICAL` (Red)**.

---

## 4. Controlled Remediation Framework

Remediation can be conducted via two distinct operational models:

### Model 1: Administrator-Triggered (Human-in-the-Loop) Remediation
*Best practice for root-cause forensic analysis before altering system state.*

1. **Alert Receipt:** Administrator observes the Nagios alert and identifies the drifted resource.
2. **Triage:** Administrator inspects `/var/log/auth.log` or bash history to determine how the drift occurred.
3. **Trigger Puppet Convergence:**  
   On the **Managed Client**, run:
   ```bash
   sudo puppet agent -t
   ```
   Puppet compiles the authoritative catalog from `puppetmaster.ec2.internal` and applies idempotent corrections:
   ```text
   Info: Using configured environment 'production'
   Info: Retrieving pluginfacts
   Info: Retrieving plugin
   Info: Caching catalog for client.ec2.internal
   Info: Applying configuration version '...'
   Notice: /Stage[main]/Security_baseline::Ssh/File[/etc/ssh/sshd_config]/content: content changed '{md5}...' to '{md5}...'
   Notice: /Stage[main]/Security_baseline::Ssh/Service[ssh]: Triggered 'refresh' from 1 event
   Notice: /Stage[main]/Security_baseline::File_permissions/File[/etc/shadow]/mode: mode changed '0666' to '0640'
   Notice: /Stage[main]/Security_baseline::Services/Service[auditd]/ensure: ensure changed 'stopped' to 'running'
   Notice: Applied catalog in 2.14 seconds
   ```

4. **Verify Recovery:**  
   Re-run the rollup compliance probe:
   ```bash
   /usr/local/lib/nagios/plugins/check_security_baseline.sh
   echo "Exit Code: $?"
   ```
   Expected output:
   ```text
   OK - Complete security baseline is compliant across SSH, daemons, permissions, and Puppet Agent.
    - Puppet Agent: ACTIVE
    - SSH Check: COMPLIANT
    - Security Services: ACTIVE
    - File Permissions: SECURE
   Exit Code: 0
   ```
5. **Nagios Recovery:**  
   Nagios service checks refresh on the next cycle, automatically resetting to **`OK` (Green)**.

---

### Model 2: Autonomous Continuous Enforcement (Daemon Mode)

In production environments requiring autonomous self-healing without manual intervention:
1. Ensure the Puppet Agent background service is active:
   ```bash
   sudo systemctl enable --now puppet
   ```
2. The agent automatically executes every 30 minutes (`runinterval = 30m`). Any drift introduced will be corrected automatically on the next scheduled convergence cycle.
3. To accelerate convergence in high-security environments, configure a tighter run interval in `/etc/puppetlabs/puppet/puppet.conf`:
   ```ini
   [main]
   runinterval = 10m
   ```
