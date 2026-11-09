# Verification and Validation Checklist

**Project:** Automated Security Compliance and Configuration Drift Detection Using Puppet and Nagios on AWS EC2  
**Target Environment:** AWS EC2 (Ubuntu Linux LTS)  

Use this checklist during setup, testing, and final audit to ensure all operational, security, and academic requirements are satisfied.

---

## 1. Cloud & Network Infrastructure (AWS EC2)

- [ ] Two Ubuntu Server 22.04 LTS instances provisioned in the same VPC subnet.
- [ ] Instance types configured: `sec-compliance-mgmt` as `t3.medium`, `sec-compliance-client` as `t3.micro` (or `t3.small`).
- [ ] Separate Security Groups deployed (`sg-management` and `sg-client`).
- [ ] SSH (Port 22) restricted strictly to your public IP (`YOUR_IP/32`).
- [ ] Nagios Web UI (Port 80) restricted strictly to your public IP (`YOUR_IP/32`).
- [ ] Puppet communication (Port 8140) restricted strictly to the Client Private IP / `sg-client`.
- [ ] NRPE communication (Port 5666) restricted strictly to the Management Private IP / `sg-management`.
- [ ] ICMP echo enabled between private IPs for host availability checks.
- [ ] Both instances have hostnames configured (`puppetmaster.ec2.internal`, `client.ec2.internal`).
- [ ] `/etc/hosts` contains bidirectional private IP mappings on both instances.

---

## 2. Configuration Management Tier (Puppet)

- [ ] Official Puppet 7.x/8.x APT repository installed on both nodes.
- [ ] `puppetserver` installed on Management Server with JVM memory tuned (`-Xms1536m -Xmx1536m`).
- [ ] Puppet CA initialized and listening on port 8140.
- [ ] `puppet-agent` installed on Client and configured with server `puppetmaster.ec2.internal`.
- [ ] Client certificate request submitted and successfully signed by CA.
- [ ] Test run (`puppet agent -t`) completes with zero compilation errors.
- [ ] Primary manifest `puppet/manifests/site.pp` deploys without syntax errors.
- [ ] Puppet background service enabled and active on Client (`systemctl is-active puppet`).

---

## 3. Security Baseline Hardening Controls

- [ ] OpenSSH server hardened: `PermitRootLogin no` enforced in `/etc/ssh/sshd_config`.
- [ ] Password authentication restricted according to lab policy (`PasswordAuthentication no`).
- [ ] `MaxAuthTries` configured to `<= 4`.
- [ ] SSH configuration validated with `validate_cmd` before daemon reload.
- [ ] Sensitive file permissions strictly enforced:
  - [ ] `/etc/shadow` set to `0640`, owner `root`, group `shadow`.
  - [ ] `/etc/gshadow` set to `0640`, owner `root`, group `shadow`.
  - [ ] `/etc/passwd` set to `0644`, owner `root`, group `root`.
  - [ ] `/etc/group` set to `0644`, owner `root`, group `root`.
  - [ ] `/etc/crontab` set to `0600`, owner `root`, group `root`.
- [ ] Essential security daemons running and enabled:
  - [ ] `auditd` active.
  - [ ] `ufw` active.
  - [ ] `systemd-timesyncd` active.
- [ ] Insecure legacy services purged (`telnet`, `rsh-client`, `talk`, `xinetd`).
- [ ] Kernel sysctl network hardening applied (`rp_filter = 1`, `icmp_echo_ignore_broadcasts = 1`).

---

## 4. Monitoring & Alerting Tier (Nagios Core & NRPE)

- [ ] Nagios Core 4.4.x compiled and installed on Management Server.
- [ ] Apache web interface configured with `nagiosadmin` authentication.
- [ ] Official Nagios Plugins compiled and installed in `/usr/local/nagios/libexec/`.
- [ ] `check_nrpe` client binary compiled with SSL support.
- [ ] Nagios configuration files deployed:
  - [ ] `commands.cfg` defines `check_nrpe`, `check_ssh`, `check_http`, `check-host-alive`.
  - [ ] `hosts.cfg` defines `sec-compliance-mgmt` and `sec-compliance-client`.
  - [ ] `services.cfg` defines 10 infrastructure and compliance services.
- [ ] Nagios pre-flight configuration check passes (`nagios -v nagios.cfg`) with 0 errors and 0 warnings.
- [ ] NRPE daemon installed and active on Client (`nagios-nrpe-server`).
- [ ] `/etc/nagios/nrpe.cfg` restricts `allowed_hosts` to the Management Server Private IP.
- [ ] All custom commands registered in `/etc/nagios/nrpe.cfg`.

---

## 5. Independent Compliance Check Plugins

- [ ] `check_ssh_security.sh` returns `Exit 0` when compliant and `Exit 2` when drifted.
- [ ] `check_services.sh` validates required vs. forbidden services with deterministic return codes.
- [ ] `check_file_permissions.sh` identifies world-writable files and permissions leaks.
- [ ] `check_security_baseline.sh` provides an accurate composite rollup status.
- [ ] All scripts are executable (`chmod +x`) and located in `/usr/local/lib/nagios/plugins/`.
- [ ] Scripts do not depend on Puppet state or cached reports (independent live OS inspection).

---

## 6. Configuration Drift & Remediation Lifecycle

- [ ] **Steady-State:** All Nagios services display **OK (Green)**.
- [ ] **Drift Injection:** Manual modification of `/etc/ssh/sshd_config` (`PermitRootLogin yes`) introduced.
- [ ] **Detection:** `check_ssh_security.sh` detects drift immediately; Nagios triggers **CRITICAL (Red)** alert.
- [ ] **Root-Cause Analysis:** Drift details verified via Nagios alert message and terminal inspection.
- [ ] **Remediation Trigger:** `sudo puppet agent -t` executed; Puppet reverts file and reloads SSH daemon.
- [ ] **Recovery:** `check_ssh_security.sh` returns `Exit 0`; Nagios clears alert back to **OK (Green)**.

---

## 7. Verification Evidence & Documentation

- [ ] All 8 test scenarios executed and actual outputs documented in `tests/test-plan.md`.
- [ ] Screenshots captured and stored in `screenshots/`:
  - [ ] `test-01-ec2-connectivity.png`
  - [ ] `test-02-puppet-cert-agent.png`
  - [ ] `test-03-puppet-baseline-apply.png`
  - [ ] `test-04-nagios-initial-dashboard.png`
  - [ ] `test-05-drift-injection.png`
  - [ ] `test-06-nagios-drift-alert.png`
  - [ ] `test-07-puppet-remediation.png`
  - [ ] `test-08-compliance-restored.png`
- [ ] Zero secrets, passwords, or `.pem` keys committed to Git.

