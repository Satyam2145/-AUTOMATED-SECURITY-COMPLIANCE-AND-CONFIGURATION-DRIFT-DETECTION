# Comprehensive Test Plan: Security Baseline & Drift Remediation

**Project:** Automated Security Compliance and Configuration Drift Detection Using Puppet and Nagios on AWS EC2  
**Target Environment:** AWS EC2 (Ubuntu Linux LTS)  
**Author:** Satyam Sharma  

---

## 1. Overview and Test Objectives

This document details the formal 8-scenario test suite designed to empirically validate the system's ability to:
1. Establish secure cloud networking and server reachability.
2. Maintain mutual TLS certificate authentication between Puppet Server and Agent.
3. Declaratively enforce an authoritative security baseline.
4. Continuously monitor host health and compliance states via Nagios Core & NRPE.
5. Reliably detect configuration drift out-of-band within 120 seconds.
6. Trigger automated alerts without false positives.
7. Restore compliant state via idempotent Puppet convergence.
8. Re-evaluate and clear alerts upon recovery.

---

## 2. Test Execution Matrix

| Test ID | Scenario Description | Expected State | Validation Method |
| :---: | :--- | :---: | :--- |
| **TEST-01** | AWS EC2 Instance Reachability & Private Routing | PASS | SSH & ICMP ping over private VPC IPs |
| **TEST-02** | Puppet Agent to Server mTLS Authentication | PASS | Certificate signing and test run (`puppet agent -t`) |
| **TEST-03** | Puppet Security Baseline Enforcement | PASS | Local state convergence (`security_baseline` class) |
| **TEST-04** | Nagios Baseline Health & Compliance Status | OK (Green) | Nagios Core Web UI dashboard |
| **TEST-05** | Controlled Configuration Drift Injection | DRIFTED | Manual modification of `/etc/ssh/sshd_config` |
| **TEST-06** | Real-Time Drift Alerting in Nagios | CRITICAL (Red) | `check_ssh_security` returns exit code 2 |
| **TEST-07** | Idempotent State Remediation via Puppet | RESTORED | `puppet agent -t` restores approved file content |
| **TEST-08** | Post-Remediation Compliance Verification | OK (Green) | Rollup probe returns exit code 0 |

---

## 3. Detailed Test Scenarios

### TEST-01: AWS EC2 Multi-Node Reachability and Private Routing
- **Objective:** Verify both EC2 instances are operational, SSH accessible by the administrator, and communicate over private VPC IPs.
- **Pre-conditions:** Both instances running in AWS EC2 console with security groups `sg-management` and `sg-client` attached.
- **Commands:**
  ```bash
  # From Admin Workstation:
  ssh -i devops-sec-key.pem ubuntu@<MGMT_PUBLIC_IP> "hostnamectl status"
  ssh -i devops-sec-key.pem ubuntu@<CLIENT_PUBLIC_IP> "hostnamectl status"

  # From Management Server (test private connectivity):
  ping -c 3 client.ec2.internal
  ```
- **Expected Output:**
  - Both SSH connections succeed with `ubuntu` user.
  - Hostnames match `puppetmaster.ec2.internal` and `client.ec2.internal`.
  - ICMP ping succeeds with 0% packet loss.
- **Actual Output:**
  ```text
  [Fill in during lab execution]
  ```
- **Screenshot Evidence:** Save terminal capture as `screenshots/test-01-ec2-connectivity.png`.
- **Explanation:** Proves basic network isolation, routing, and access control integrity.

---

### TEST-02: Puppet Agent to Server mTLS Authentication Handshake
- **Objective:** Verify Puppet Agent successfully submits its certificate request and establishes an encrypted mTLS session with Puppet Server.
- **Pre-conditions:** `puppetserver` running on port 8140 of Management Server; `puppet-agent` installed on Client.
- **Commands:**
  ```bash
  # On Management Server:
  sudo /opt/puppetlabs/bin/puppetserver ca list --all

  # On Managed Client:
  sudo /opt/puppetlabs/bin/puppet agent -t
  ```
- **Expected Output:**
  - `puppetserver ca list` shows signed certificate for `client.ec2.internal`.
  - `puppet agent -t` returns: `Info: Caching catalog for client.ec2.internal` and `Notice: Applied catalog in ... seconds`.
- **Actual Output:**
  ```text
  [Fill in during lab execution]
  ```
- **Screenshot Evidence:** Save terminal capture as `screenshots/test-02-puppet-cert-agent.png`.
- **Explanation:** Confirms cryptographic trust and communication integrity between management and client nodes.

---

### TEST-03: Puppet Security Baseline Enforcement
- **Objective:** Validate that the `security_baseline` module applies hardening rules (SSH, file permissions, daemons, sysctl) idempotently.
- **Pre-conditions:** `security_baseline` module installed in Puppet environment; `site.pp` includes `client.ec2.internal`.
- **Commands:**
  ```bash
  # On Managed Client:
  sudo /opt/puppetlabs/bin/puppet agent -t

  # Verify critical settings applied:
  grep "^PermitRootLogin" /etc/ssh/sshd_config
  stat -c "%a %U:%G" /etc/shadow
  systemctl is-active auditd ufw systemd-timesyncd
  ```
- **Expected Output:**
  - `PermitRootLogin` outputs `PermitRootLogin no`.
  - `/etc/shadow` outputs `640 root:shadow`.
  - All three services return `active`.
- **Actual Output:**
  ```text
  [Fill in during lab execution]
  ```
- **Screenshot Evidence:** Save terminal capture as `screenshots/test-03-puppet-baseline-apply.png`.
- **Explanation:** Proves declarative configuration management successfully applies standard Linux hardening benchmarks.

---

### TEST-04: Nagios Baseline Health & Compliance Status
- **Objective:** Verify Nagios Core discovers the managed client and reports all standard services and compliance probes as `OK` (Green).
- **Pre-conditions:** Nagios Core running on Management Server; NRPE running on Client; custom scripts placed in `/usr/local/lib/nagios/plugins/`.
- **Commands:**
  ```bash
  # On Management Server:
  /usr/local/nagios/libexec/check_nrpe -H client.ec2.internal -c check_security_baseline
  ```
  Open browser: `http://<MGMT_PUBLIC_IP>/nagios/` -> Services.
- **Expected Output:**
  - CLI output: `OK - Complete security baseline is compliant...` (Exit 0).
  - Web UI: All 10 services on `sec-compliance-client` show green `OK` status.
- **Actual Output:**
  ```text
  [Fill in during lab execution]
  ```
- **Screenshot Evidence:** Save browser view as `screenshots/test-04-nagios-initial-dashboard.png`.
- **Explanation:** Demonstrates baseline steady-state monitoring with zero false positives.

---

### TEST-05: Controlled Configuration Drift Injection
- **Objective:** Introduce an intentional out-of-band configuration modification to simulate an administrative error or unauthorized intrusion.
- **Pre-conditions:** System in steady-state (Test 4 complete).
- **Commands:**
  ```bash
  # On Managed Client:
  sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  sudo systemctl reload ssh

  # Confirm drift is active on filesystem:
  grep "^PermitRootLogin" /etc/ssh/sshd_config
  ```
- **Expected Output:**
  - Outputs `PermitRootLogin yes`.
  - SSH daemon reloads successfully with non-compliant configuration.
- **Actual Output:**
  ```text
  [Fill in during lab execution]
  ```
- **Screenshot Evidence:** Save terminal view as `screenshots/test-05-drift-injection.png`.
- **Explanation:** Establishes a controlled vulnerability scenario for empirical drift detection testing.

---

### TEST-06: Real-Time Drift Alerting in Nagios
- **Objective:** Verify that Nagios detects the unauthorized SSH configuration drift out-of-band and transitions the service to `CRITICAL`.
- **Pre-conditions:** Drift injected (Test 5 complete).
- **Commands:**
  ```bash
  # On Managed Client (local script test):
  /usr/local/lib/nagios/plugins/check_ssh_security.sh
  echo "Exit Code: $?"

  # On Management Server (NRPE probe query):
  /usr/local/nagios/libexec/check_nrpe -H client.ec2.internal -c check_ssh_security
  echo "Exit Code: $?"
  ```
  Refresh Nagios Core Web UI.
- **Expected Output:**
  - CLI output: `CRITICAL - SSH Configuration Drift Detected: PermitRootLogin is set to 'yes' (Policy requires 'no')`.
  - Exit code is `2`.
  - Nagios dashboard displays `DRIFT: SSH Security Hardening` in **CRITICAL (Red)** state.
- **Actual Output:**
  ```text
  [Fill in during lab execution]
  ```
- **Screenshot Evidence:** Save browser alert view as `screenshots/test-06-nagios-drift-alert.png`.
- **Explanation:** Confirms independent, real-time drift detection without relying on Puppet's scheduled polling cycle.

---

### TEST-07: Idempotent State Remediation via Puppet
- **Objective:** Trigger configuration management convergence to restore the approved baseline and correct the drifted setting.
- **Pre-conditions:** System in CRITICAL state (Test 6 complete).
- **Commands:**
  ```bash
  # On Managed Client:
  sudo /opt/puppetlabs/bin/puppet agent -t

  # Inspect restored file:
  grep "^PermitRootLogin" /etc/ssh/sshd_config
  ```
- **Expected Output:**
  - Puppet notices content change in `/etc/ssh/sshd_config` and reloads `ssh` service.
  - File now contains `PermitRootLogin no`.
- **Actual Output:**
  ```text
  [Fill in during lab execution]
  ```
- **Screenshot Evidence:** Save terminal remediation output as `screenshots/test-07-puppet-remediation.png`.
- **Explanation:** Proves Puppet's declarative idempotency corrects runtime drift back to the authoritative repository baseline.

---

### TEST-08: Post-Remediation Compliance Verification
- **Objective:** Verify that compliance audit probes confirm restored compliance and Nagios automatically clears the alert to `OK`.
- **Pre-conditions:** Remediation executed (Test 7 complete).
- **Commands:**
  ```bash
  # On Managed Client:
  /usr/local/lib/nagios/plugins/check_ssh_security.sh
  echo "Exit Code: $?"

  /usr/local/lib/nagios/plugins/check_security_baseline.sh
  echo "Exit Code: $?"
  ```
  Wait for next Nagios check cycle (or force check via Web UI -> "Re-schedule the next check of this service").
- **Expected Output:**
  - Both plugins exit with code `0` (OK).
  - Nagios Web UI shifts the service from CRITICAL back to **OK (Green)**.
- **Actual Output:**
  ```text
  [Fill in during lab execution]
  ```
- **Screenshot Evidence:** Save restored dashboard as `screenshots/test-08-compliance-restored.png`.
- **Explanation:** Completes the closed-loop governance cycle: Detection -> Alert -> Remediation -> Recovery.

