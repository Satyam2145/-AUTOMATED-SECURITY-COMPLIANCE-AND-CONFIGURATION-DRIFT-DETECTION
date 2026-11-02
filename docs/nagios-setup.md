# Nagios Core & NRPE Monitoring Setup Guide

**Project:** Automated Security Compliance and Configuration Drift Detection Using Puppet and Nagios on AWS EC2  
**Target Platform:** Ubuntu Server 22.04 LTS (Jammy Jellyfish)  
**Software:** Nagios Core 4.4.x, Nagios Plugins 2.4.x, NRPE v4  

---

## 1. Overview and Architecture

The monitoring tier provides continuous, independent observation of infrastructure health and compliance state:
- **Nagios Core (`sec-compliance-mgmt`):** Coordinates scheduled checks, evaluates return codes, renders the web interface, and dispatches alerts upon state transitions.
- **NRPE (`sec-compliance-client`):** Listens on TCP port 5666 for authorized queries from the Management Server and executes local compliance inspection scripts, returning standard exit codes (`0`, `1`, `2`, `3`).

```
+-----------------------------------------------------+            +-----------------------------------------------------+
|         Management Server (sec-compliance-mgmt)     |            |         Managed Client (sec-compliance-client)      |
|                                                     |            |                                                     |
|  +--------------------+    +---------------------+  |  TCP 5666  |  +---------------------+    +--------------------+  |
|  | Nagios Core Engine |===>| check_nrpe Plugin   |==============>|  | nagios-nrpe-server  |===>| Compliance Scripts |  |
|  +--------------------+    +---------------------+  |  Encrypted |  +---------------------+    +--------------------+  |
|          |                                          |            |                                | (Reads OS State)   |
|          v                                          |            |                                v                    |
|  +--------------------+                             |            |                     [ /etc/ssh/sshd_config ]        |
|  | Apache Web UI (:80)|                             |            |                     [ Critical File Modes  ]        |
|  +--------------------+                             |            |                     [ Active Daemons       ]        |
+-----------------------------------------------------+            +-----------------------------------------------------+
```

---

## 2. Nagios Core Installation (Management Server)

Connect via SSH to **Instance 1 (`sec-compliance-mgmt`)**:

### Step 2.1: Install Build Dependencies and Apache
```bash
sudo apt-get update
sudo apt-get install -y autoconf gcc libc6 make wget unzip apache2 php \
    libapache2-mod-php libgd-dev libssl-dev bc gawk dc build-essential \
    snmp libnet-snmp-perl gettext
```

### Step 2.2: Download and Compile Nagios Core
```bash
cd /tmp
wget -O nagioscore.tar.gz https://github.com/NagiosEnterprises/nagioscore/archive/nagios-4.4.14.tar.gz
tar xzf nagioscore.tar.gz
cd nagioscore-nagios-4.4.14/

# Configure with Apache sites configuration
sudo ./configure --with-httpd-conf=/etc/apache2/sites-enabled

# Compile binaries
sudo make all

# Create system users and groups (nagios, nagcmd)
sudo make install-groups-users
sudo usermod -a -G nagios www-data

# Install binaries, init scripts, and sample configs
sudo make install
sudo make install-daemoninit
sudo make install-commandmode
sudo make install-config
sudo make install-webconf
```

### Step 2.3: Configure Apache and Web Authentication
Enable the required Apache modules:
```bash
sudo a2enmod rewrite
sudo a2enmod cgi
```

Create the administrative user (`nagiosadmin`) for web console access:
```bash
sudo htpasswd -c /usr/local/nagios/etc/htpasswd.users nagiosadmin
```
*(Enter a strong password when prompted, e.g., `DevopsAdmin2026!`)*

Restart Apache to activate the configuration:
```bash
sudo systemctl restart apache2
```

---

### Step 2.4: Install Official Nagios Plugins
```bash
cd /tmp
wget --no-check-certificate -O nagios-plugins.tar.gz https://github.com/nagios-plugins/nagios-plugins/releases/download/release-2.4.6/nagios-plugins-2.4.6.tar.gz
tar zxf nagios-plugins.tar.gz
cd nagios-plugins-2.4.6/

sudo ./configure
sudo make
sudo make install
```

Plugins will be installed into `/usr/local/nagios/libexec/`.

---

### Step 2.5: Compile and Install `check_nrpe` Plugin
The `check_nrpe` client binary is required for Nagios to query remote NRPE daemons:
```bash
cd /tmp
wget https://github.com/NagiosEnterprises/nrpe/releases/download/nrpe-4.1.0/nrpe-4.1.0.tar.gz
tar xzf nrpe-4.1.0.tar.gz
cd nrpe-4.1.0/

./configure --enable-ssl
make check_nrpe
sudo cp src/check_nrpe /usr/local/nagios/libexec/
sudo chmod 755 /usr/local/nagios/libexec/check_nrpe
```

Verify the plugin:
```bash
/usr/local/nagios/libexec/check_nrpe -h
```

---

## 3. Integrating Project Monitoring Definitions

To link the project's repository configuration files into Nagios Core:

### Step 3.1: Deploy Configuration Files
Copy or symlink the configuration files from the repository into `/usr/local/nagios/etc/objects/`:
```bash
# Create custom configuration directory
sudo mkdir -p /usr/local/nagios/etc/devops

# Copy configuration files from the project repository
sudo cp nagios/hosts.cfg /usr/local/nagios/etc/devops/hosts.cfg
sudo cp nagios/services.cfg /usr/local/nagios/etc/devops/services.cfg
sudo cp nagios/commands.cfg /usr/local/nagios/etc/devops/commands.cfg
```

### Step 3.2: Register Configurations in `nagios.cfg`
Edit `/usr/local/nagios/etc/nagios.cfg` to include the new configuration files:
```bash
sudo bash -c 'cat <<EOF >> /usr/local/nagios/etc/nagios.cfg

# DevOps Project Security Compliance & Drift Monitoring
cfg_file=/usr/local/nagios/etc/devops/commands.cfg
cfg_file=/usr/local/nagios/etc/devops/hosts.cfg
cfg_file=/usr/local/nagios/etc/devops/services.cfg
EOF'
```

### Step 3.3: Verify Configuration Syntax and Start Service
Always validate Nagios configuration syntax before restarting the daemon:
```bash
sudo /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg
```
Ensure output reports:
```text
Total Warnings: 0
Total Errors:   0
Things look okay - No serious problems were detected during the pre-flight check
```

Start and enable the Nagios service:
```bash
sudo systemctl enable nagios
sudo systemctl start nagios
sudo systemctl status nagios --no-pager
```

Access the Web UI in your browser:
```text
http://<MANAGEMENT_SERVER_PUBLIC_IP>/nagios/
Username: nagiosadmin
```

---

## 4. NRPE Daemon Setup (Managed Client)

Connect via SSH to **Instance 2 (`sec-compliance-client`)**:

### Step 4.1: Install NRPE Server and Plugins
```bash
sudo apt-get update
sudo apt-get install -y nagios-nrpe-server nagios-plugins
```

### Step 4.2: Create Directory for Custom Compliance Probes
```bash
sudo mkdir -p /usr/local/lib/nagios/plugins
sudo chown -R root:nagios /usr/local/lib/nagios/plugins
sudo chmod -R 750 /usr/local/lib/nagios/plugins
```

Deploy the custom compliance scripts from the repository into `/usr/local/lib/nagios/plugins/`:
```bash
# Copy scripts from repository
sudo cp scripts/check_*.sh /usr/local/lib/nagios/plugins/
sudo chmod +x /usr/local/lib/nagios/plugins/*.sh
```

### Step 4.3: Create Memory Check Plugin (`check_mem.sh`)
```bash
sudo bash -c 'cat << "EOF" > /usr/local/lib/nagios/plugins/check_mem.sh
#!/bin/bash
TOTAL=$(free -m | awk "/^Mem:/ {print \$2}")
USED=$(free -m | awk "/^Mem:/ {print \$3}")
PERCENT=$((USED * 100 / TOTAL))

if [ "$PERCENT" -ge 90 ]; then
    echo "CRITICAL - Memory utilization is ${PERCENT}% (${USED}MB/${TOTAL}MB)"
    exit 2
elif [ "$PERCENT" -ge 80 ]; then
    echo "WARNING - Memory utilization is ${PERCENT}% (${USED}MB/${TOTAL}MB)"
    exit 1
else
    echo "OK - Memory utilization is ${PERCENT}% (${USED}MB/${TOTAL}MB)"
    exit 0
fi
EOF'
sudo chmod +x /usr/local/lib/nagios/plugins/check_mem.sh
```

---

### Step 4.4: Configure Allowed Hosts in `nrpe.cfg`
Edit `/etc/nagios/nrpe.cfg` to restrict incoming connections strictly to the Management Server's Private IP (`10.0.1.50`):
```bash
sudo sed -i 's/^allowed_hosts=127.0.0.1,::1/allowed_hosts=127.0.0.1,::1,10.0.1.50/' /etc/nagios/nrpe.cfg
```

Add the command bindings at the end of `/etc/nagios/nrpe.cfg`:
```bash
sudo bash -c 'cat << "EOF" >> /etc/nagios/nrpe.cfg

# ==============================================================================
# DevOps Project Custom NRPE Command Bindings
# ==============================================================================
command[check_load]=/usr/lib/nagios/plugins/check_load -r -w 5.0,4.0,3.0 -c 10.0,8.0,6.0
command[check_disk]=/usr/lib/nagios/plugins/check_disk -w 20% -c 10% -p /
command[check_mem]=/usr/local/lib/nagios/plugins/check_mem.sh
command[check_puppet_agent]=/usr/lib/nagios/plugins/check_procs -c 1:1 -C puppet
command[check_ssh_security]=/usr/local/lib/nagios/plugins/check_ssh_security.sh
command[check_services]=/usr/local/lib/nagios/plugins/check_services.sh
command[check_file_permissions]=/usr/local/lib/nagios/plugins/check_file_permissions.sh
command[check_security_baseline]=/usr/local/lib/nagios/plugins/check_security_baseline.sh
EOF'
```

### Step 4.5: Configure Sudoers for Privileged Probes (if needed)
Certain compliance checks (such as verifying permissions on `/etc/shadow`) require elevated permissions when executed by the `nagios` user. Configure a scoped sudoers rule:
```bash
sudo bash -c 'cat <<EOF > /etc/sudoers.d/nagios_compliance
nagios ALL=(root) NOPASSWD: /usr/local/lib/nagios/plugins/check_*.sh
EOF'
sudo chmod 0440 /etc/sudoers.d/nagios_compliance
```

### Step 4.6: Start and Enable NRPE Service
```bash
sudo systemctl daemon-reload
sudo systemctl enable nagios-nrpe-server
sudo systemctl restart nagios-nrpe-server
sudo systemctl status nagios-nrpe-server --no-pager
```

---

## 5. End-to-End Handshake Verification

From the **Management Server (`sec-compliance-mgmt`)**, test NRPE connectivity:

```bash
# Test NRPE daemon communication
/usr/local/nagios/libexec/check_nrpe -H 10.0.1.60
```
Expected output:
```text
NRPE v4.0.3
```

Execute remote security compliance check via NRPE:
```bash
/usr/local/nagios/libexec/check_nrpe -H 10.0.1.60 -c check_ssh_security
```
Expected output:
```text
OK - SSH configuration conforms to security baseline. PermitRootLogin=no, PasswordAuthentication=no.
```
