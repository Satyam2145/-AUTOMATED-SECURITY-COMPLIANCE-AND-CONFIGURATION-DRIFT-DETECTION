# Practical Testing & Demonstration Guide

**Project:** Automated Security Compliance and Configuration Drift Detection Using Puppet and Nagios on AWS EC2  
**Target Environment:** AWS EC2 (Ubuntu Linux LTS)  

This guide provides step-by-step instructions for running the test scenarios, verifying system behavior, and collecting evidence for academic presentation.

---

## 1. Prerequisites and Setup Verification

Before starting tests, ensure:
1. Both EC2 instances are in the `running` state.
2. You have your private SSH key (`devops-sec-key.pem`).
3. You have opened two terminal windows:
   - **Terminal 1:** Connected to the **Management Server** (`sec-compliance-mgmt`).
   - **Terminal 2:** Connected to the **Managed Client** (`sec-compliance-client`).
4. You have the Nagios Web UI open in your browser:
   `http://<MANAGEMENT_SERVER_PUBLIC_IP>/nagios/` -> Click **Services** in the left menu.

---

## 2. Step-by-Step Test Execution

### Stage 1: Verify Infrastructure & Connectivity (Test 1)
In **Terminal 1 (Management Server)**:
```bash
# Check connectivity to Client over AWS private network
ping -c 3 client.ec2.internal
```
*Expected: 3 packets transmitted, 3 received, 0% packet loss.*

Capture screenshot: Save terminal output as `screenshots/test-01-ec2-connectivity.png`.

---

### Stage 2: Verify Puppet Certificate Trust (Test 2)
In **Terminal 1 (Management Server)**:
```bash
sudo /opt/puppetlabs/bin/puppetserver ca list --all
```
*Expected: Shows signed certificate `+ client.ec2.internal (SHA256) ...`.*

In **Terminal 2 (Managed Client)**:
```bash
sudo /opt/puppetlabs/bin/puppet agent -t
```
*Expected: `Notice: Applied catalog in ... seconds` without errors.*

Capture screenshot: Save terminal output as `screenshots/test-02-puppet-cert-agent.png`.

---

### Stage 3: Validate Puppet Baseline Application (Test 3)
In **Terminal 2 (Managed Client)**:
Verify the settings enforced by Puppet:
```bash
# 1. SSH root login
grep -E "^\s*PermitRootLogin" /etc/ssh/sshd_config

# 2. File permissions
stat -c "%a %U:%G" /etc/shadow
stat -c "%a %U:%G" /etc/passwd

# 3. Active security services
systemctl is-active auditd ufw systemd-timesyncd
```
*Expected:*
- `PermitRootLogin no`
- `640 root:shadow`
- `644 root:root`
- `active` for all daemons.

Capture screenshot: Save terminal output as `screenshots/test-03-puppet-baseline-apply.png`.

---

### Stage 4: Steady-State Nagios Dashboard (Test 4)
Open the Nagios Web Console in your browser:
`http://<MANAGEMENT_SERVER_PUBLIC_IP>/nagios/cgi-bin/status.cgi?host=all`

*Expected:*
All services on `sec-compliance-client` (including `DRIFT: SSH Security Hardening`, `DRIFT: Security Services Execution`, and `DRIFT: Critical File Permissions`) must display **`OK` (Green)**.

Capture screenshot: Save browser window as `screenshots/test-04-nagios-initial-dashboard.png`.

---

### Stage 5: Inject Configuration Drift (Test 5)
Now simulate an unauthorized change by an intruder or developer troubleshooting via SSH.

In **Terminal 2 (Managed Client)**:
```bash
# Modify SSH configuration to allow root login
sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sudo systemctl reload ssh

# Confirm the file now contains the non-compliant setting:
grep "^PermitRootLogin" /etc/ssh/sshd_config
```
*Expected: Outputs `PermitRootLogin yes`.*

Capture screenshot: Save terminal output as `screenshots/test-05-drift-injection.png`.

---

### Stage 6: Observe Real-Time Nagios Alert (Test 6)
In **Terminal 2 (Managed Client)**:
Run the compliance script manually to observe immediate detection:
```bash
/usr/local/lib/nagios/plugins/check_ssh_security.sh
echo "Exit Code: $?"
```
*Expected:*
```text
CRITICAL - SSH Configuration Drift Detected: PermitRootLogin is set to 'yes' (Policy requires 'no') | permit_root_login=yes password_auth=no
Exit Code: 2
```

In the **Nagios Web Console**:
Wait up to 120 seconds (the check interval), or click on `DRIFT: SSH Security Hardening` -> **Re-schedule the next check of this service** -> click **Commit**.

*Expected:*
The service transitions to **`CRITICAL` (Red)** with the alert text matching the script output.

Capture screenshot: Save browser view as `screenshots/test-06-nagios-drift-alert.png`.

---

### Stage 7: Remediate Drift via Puppet (Test 7)
In **Terminal 2 (Managed Client)**:
Trigger Puppet declarative state convergence:
```bash
sudo /opt/puppetlabs/bin/puppet agent -t
```
*Expected:*
```text
Notice: /Stage[main]/Security_baseline::Ssh/File[/etc/ssh/sshd_config]/content: content changed '{md5}...' to '{md5}...'
Notice: /Stage[main]/Security_baseline::Ssh/Service[ssh]: Triggered 'refresh' from 1 event
Notice: Applied catalog in ... seconds
```

Verify that the file has been restored:
```bash
grep "^PermitRootLogin" /etc/ssh/sshd_config
```
*Expected: Outputs `PermitRootLogin no`.*

Capture screenshot: Save terminal output as `screenshots/test-07-puppet-remediation.png`.

---

### Stage 8: Verify Compliance Recovery in Nagios (Test 8)
In **Terminal 2 (Managed Client)**:
Re-run the compliance rollup probe:
```bash
/usr/local/lib/nagios/plugins/check_security_baseline.sh
echo "Exit Code: $?"
```
*Expected: Returns `Exit Code: 0`.*

In the **Nagios Web Console**:
Re-schedule the service check or wait for the automatic polling cycle.

*Expected:*
The service turns back to **`OK` (Green)** and the incident is marked as recovered.

Capture screenshot: Save restored browser view as `screenshots/test-08-compliance-restored.png`.
