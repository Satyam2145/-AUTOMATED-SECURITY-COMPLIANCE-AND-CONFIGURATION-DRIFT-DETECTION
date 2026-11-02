# DevOps Troubleshooting Runbook & Diagnostics

**Project:** Automated Security Compliance and Configuration Drift Detection Using Puppet and Nagios on AWS EC2  
**Target Platform:** Ubuntu Server 22.04 LTS on AWS EC2  

This runbook documents common failures, diagnostic procedures, and validated recovery solutions for all tiers of the project.

---

## 1. Puppet Configuration Management Troubleshooting

### Problem 1.1: Puppet Agent Certificate Verification Failure
**Symptom:**  
When running `puppet agent -t` on the client, you receive:
```text
Error: Certificate verify failed [certificate signature failure]
Error: Could not request certificate: SSL_connect returned=1 errno=0 error: ...
```
**Root Cause:**  
The client's hostname was changed after certificate creation, or the server's CA was re-initialized without resetting the client's local SSL directory.

**Resolution:**
1. On the **Management Server**, revoke and remove the client's certificate:
   ```bash
   sudo /opt/puppetlabs/bin/puppetserver ca clean --certname client.ec2.internal
   ```
2. On the **Managed Client**, remove the stale SSL directory:
   ```bash
   sudo rm -rf /etc/puppetlabs/puppet/ssl
   ```
3. On the **Managed Client**, submit a fresh certificate request:
   ```bash
   sudo /opt/puppetlabs/bin/puppet agent -t
   ```
4. On the **Management Server**, sign the new certificate:
   ```bash
   sudo /opt/puppetlabs/bin/puppetserver ca sign --certname client.ec2.internal
   ```
5. On the **Managed Client**, re-run the agent:
   ```bash
   sudo /opt/puppetlabs/bin/puppet agent -t
   ```

---

### Problem 1.2: Puppet Server JVM Out-Of-Memory (OOM) Crash
**Symptom:**  
`systemctl status puppetserver` shows `active (exited)` or fails with `java.lang.OutOfMemoryError: Java heap space`. The OS syslog reports the Linux OOM-killer killed `java`.

**Root Cause:**  
The default heap allocation of 2 GiB is too large for an EC2 `t3.medium` instance sharing memory with Nagios Core and Apache.

**Resolution:**
1. Check available RAM and swap:
   ```bash
   free -m
   ```
2. Edit `/etc/default/puppetserver` and reduce the heap size to 1.5 GiB (or 1 GiB):
   ```bash
   sudo sed -i 's/-Xms2g -Xmx2g/-Xms1536m -Xmx1536m/' /etc/default/puppetserver
   ```
3. Restart Puppet Server:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart puppetserver
   ```

---

### Problem 1.3: SSH Daemon Validation Failure in Puppet Manifest
**Symptom:**  
Puppet catalog fails with:
```text
Error: /Stage[main]/Security_baseline::Ssh/File[/etc/ssh/sshd_config]: Could not evaluate: Validation of ... failed
```
**Explanation & Safety Feature:**  
This is Puppet's built-in safety mechanism working as intended. The `validate_cmd => '/usr/sbin/sshd -t -f %'` parameter tests the candidate file with the SSH daemon binary before replacing the active file. If a typo exists in the template, Puppet refuses to write the file, completely protecting the administrator from SSH lockout!

**Resolution:**
Inspect the syntax error:
```bash
sudo /usr/sbin/sshd -t -f /path/to/template
```
Correct the parameter syntax in `puppet/modules/security_baseline/templates/sshd_config.epp`.

---

## 2. Nagios Core & NRPE Troubleshooting

### Problem 2.1: `CHECK_NRPE: Error - Could not complete SSL handshake`
**Symptom:**  
When executing `check_nrpe` from the Management Server:
```bash
/usr/local/nagios/libexec/check_nrpe -H 10.0.1.60
CHECK_NRPE: Error - Could not complete SSL handshake.
```
**Root Causes & Diagnosis:**
1. The Management Server's Private IP is missing from `allowed_hosts` in `/etc/nagios/nrpe.cfg` on the Client.
2. The NRPE daemon on the Client is bound to `127.0.0.1` instead of `0.0.0.0` or its private interface.
3. AWS Security Group `sg-client` is blocking TCP port 5666 from `sg-management`.

**Resolution:**
1. On the **Managed Client**, verify the `allowed_hosts` directive:
   ```bash
   grep "^allowed_hosts" /etc/nagios/nrpe.cfg
   ```
   Ensure it includes your Management Server Private IP (e.g., `10.0.1.50`):
   ```text
   allowed_hosts=127.0.0.1,::1,10.0.1.50
   ```
2. Verify port 5666 is listening on all interfaces:
   ```bash
   sudo ss -tulpn | grep 5666
   ```
   Must display `0.0.0.0:5666` or `*:5666`.
3. Restart NRPE daemon:
   ```bash
   sudo systemctl restart nagios-nrpe-server
   ```

---

### Problem 2.2: NRPE Returns `NRPE: Command 'check_xyz' not defined`
**Symptom:**  
Nagios displays service state `UNKNOWN` with status `NRPE: Command 'check_ssh_security' not defined`.

**Resolution:**
1. Check the command definitions in `/etc/nagios/nrpe.cfg` on the Managed Client:
   ```bash
   grep "check_ssh_security" /etc/nagios/nrpe.cfg
   ```
2. If missing, register the command:
   ```bash
   sudo bash -c 'echo "command[check_ssh_security]=/usr/local/lib/nagios/plugins/check_ssh_security.sh" >> /etc/nagios/nrpe.cfg'
   sudo systemctl restart nagios-nrpe-server
   ```

---

### Problem 2.3: Script Permission Denied (`Return code of 126 / 127 is out of bounds`)
**Symptom:**  
Nagios displays `CRITICAL` or `UNKNOWN` with: `(Return code of 126 is out of bounds - plugin may not be executable)`.

**Resolution:**
Ensure execution permissions are set on the scripts directory on the Managed Client:
```bash
sudo chmod +x /usr/local/lib/nagios/plugins/*.sh
sudo chown -R root:nagios /usr/local/lib/nagios/plugins
```
Test script execution as the `nagios` user:
```bash
sudo -u nagios /usr/local/lib/nagios/plugins/check_ssh_security.sh
```

---

## 3. Nagios Web Interface Access Troubleshooting

### Problem 3.1: HTTP 403 Forbidden on `/nagios/`
**Symptom:**  
Navigating to `http://<MGMT_PUBLIC_IP>/nagios/` returns `403 Forbidden` or Apache default page.

**Resolution:**
1. Ensure Apache CGI and rewrite modules are enabled:
   ```bash
   sudo a2enmod cgi
   sudo a2enmod rewrite
   sudo systemctl restart apache2
   ```
2. Verify Nagios Apache configuration exists in `/etc/apache2/sites-enabled/`:
   ```bash
   ls -la /etc/apache2/sites-enabled/nagios.conf
   ```
3. If missing, re-link from `/etc/apache2/sites-available/nagios.conf` and restart Apache:
   ```bash
   sudo a2ensite nagios.conf
   sudo systemctl restart apache2
   ```

---

### Problem 3.2: Nagios Web Authentication Fails Repeatedly
**Symptom:**  
Browser prompts for credentials continuously and refuses access.

**Resolution:**
Re-create the `nagiosadmin` user password in the authentication file:
```bash
sudo htpasswd -b -c /usr/local/nagios/etc/htpasswd.users nagiosadmin YourNewPassword123!
sudo systemctl restart apache2
```
Verify browser connects using `nagiosadmin` and the newly set password.
