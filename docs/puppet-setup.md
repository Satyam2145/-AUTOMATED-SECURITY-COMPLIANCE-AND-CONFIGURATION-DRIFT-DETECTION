# Puppet Server and Agent Installation & Configuration Guide

**Project:** Automated Security Compliance and Configuration Drift Detection Using Puppet and Nagios on AWS EC2  
**Target Platform:** Ubuntu Server 22.04 LTS (Jammy Jellyfish)  
**Software:** Puppet 7.x (Enterprise LTS Standard) / Puppet 8.x  

---

## 1. Overview and Architecture

Puppet operates on a declarative **Client-Server model** secured via **Mutual TLS (mTLS)**:
- **Puppet Server (`sec-compliance-mgmt`):** Functions as the Certificate Authority (CA), compiles catalog configurations, and distributes desired states.
- **Puppet Agent (`sec-compliance-client`):** Sends node facts, pulls the compiled catalog, converges the local system to the desired state, and reports compliance status.

```
+------------------------------------+               +----------------------------------+
|   Management Server (t3.medium)    |               |    Managed Client (t3.micro)     |
|   puppetmaster.ec2.internal        |               |    client.ec2.internal           |
|                                    |   TCP 8140    |                                  |
|   +----------------------------+   |  mTLS Handshake  +----------------------------+  |
|   |   Puppet CA & Server       |<==================|   Puppet Agent             |  |
|   |   (JVM Heap: 1.5 GiB)      |   Catalog Sync    |   (/etc/puppetlabs/puppet) |  |
|   +----------------------------+   |               +----------------------------+  |
+------------------------------------+               +----------------------------------+
```

---

## 2. Prerequisites Verification

Before beginning installation, verify hostname resolution and private connectivity between instances.

### On Both Instances:
Ensure `/etc/hosts` includes:
```bash
# Verify DNS resolution on both servers
cat /etc/hosts | grep ec2.internal
```
Output must contain:
```text
10.0.1.50   puppetmaster.ec2.internal puppetmaster puppet
10.0.1.60   client.ec2.internal client
```

Test network reachability from Client to Server:
```bash
ping -c 2 puppetmaster.ec2.internal
```

---

## 3. Puppet Server Installation (Management Server)

Connect to **Instance 1 (`sec-compliance-mgmt`)**:

### Step 3.1: Add the Official Puppet Repository
```bash
cd /tmp
wget https://apt.puppet.com/puppet7-release-jammy.deb
sudo dpkg -i puppet7-release-jammy.deb
sudo apt-get update
```

### Step 3.2: Install Puppet Server
```bash
sudo apt-get install -y puppetserver
```

Add Puppet binaries to standard system PATH:
```bash
echo 'export PATH=/opt/puppetlabs/bin:$PATH' | sudo tee /etc/profile.d/puppet.sh
source /etc/profile.d/puppet.sh
```

### Step 3.3: JVM Memory Tuning (Critical for `t3.medium`)
By default, Puppet Server allocates 2 GiB of JVM heap space. To ensure stability alongside Nagios Core and Apache on `t3.medium`, tune the memory allocation to **1.5 GiB** (or 1 GiB):

Edit `/etc/default/puppetserver`:
```bash
sudo sed -i 's/-Xms2g -Xmx2g/-Xms1536m -Xmx1536m/' /etc/default/puppetserver
```

Verify the setting:
```bash
grep "JAVA_ARGS" /etc/default/puppetserver
```
Expected output:
```text
JAVA_ARGS="-Xms1536m -Xmx1536m -Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger"
```

### Step 3.4: Configure Puppet Server (`puppet.conf`)
Edit `/etc/puppetlabs/puppet/puppet.conf`:
```bash
sudo bash -c 'cat <<EOF > /etc/puppetlabs/puppet/puppet.conf
[server]
vardir = /opt/puppetlabs/server/data/puppetserver
logdir = /var/log/puppetlabs/puppetserver
rundir = /var/run/puppetlabs/puppetserver
pidfile = /var/run/puppetlabs/puppetserver/puppetserver.pid
codedir = /etc/puppetlabs/code
dns_alt_names = puppetmaster,puppet,puppetmaster.ec2.internal

[main]
certname = puppetmaster.ec2.internal
server = puppetmaster.ec2.internal
environment = production
runinterval = 30m
EOF'
```

### Step 3.5: Initialize CA and Start Puppet Server
```bash
# Initialize CA certificates
sudo /opt/puppetlabs/bin/puppetserver ca setup

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable puppetserver
sudo systemctl start puppetserver
```

Verify service status:
```bash
sudo systemctl status puppetserver --no-pager
```

Verify that Puppet Server is listening on port 8140:
```bash
sudo ss -tulpn | grep 8140
```
Expected output:
```text
tcp   LISTEN 0      50          *:8140             *:*    users:(("java",pid=...,fd=...))
```

---

## 4. Puppet Agent Installation (Managed Client)

Connect to **Instance 2 (`sec-compliance-client`)**:

### Step 4.1: Add the Official Puppet Repository
```bash
cd /tmp
wget https://apt.puppet.com/puppet7-release-jammy.deb
sudo dpkg -i puppet7-release-jammy.deb
sudo apt-get update
```

### Step 4.2: Install Puppet Agent
```bash
sudo apt-get install -y puppet-agent
```

Configure PATH:
```bash
echo 'export PATH=/opt/puppetlabs/bin:$PATH' | sudo tee /etc/profile.d/puppet.sh
source /etc/profile.d/puppet.sh
```

### Step 4.3: Configure Puppet Agent (`puppet.conf`)
Edit `/etc/puppetlabs/puppet/puppet.conf`:
```bash
sudo bash -c 'cat <<EOF > /etc/puppetlabs/puppet/puppet.conf
[main]
certname = client.ec2.internal
server = puppetmaster.ec2.internal
environment = production
runinterval = 30m
EOF'
```

---

## 5. Mutual TLS Certificate Signing & Handshake

To secure communications, Puppet uses mutual TLS authentication. The Client must request a certificate from the Server's CA.

### Step 5.1: Submit Certificate Request from Client
On the **Managed Client**:
```bash
sudo /opt/puppetlabs/bin/puppet agent -t
```
Expected output:
```text
Info: Creating a new RSA SSL key for client.ec2.internal
Info: Certificate Request fingerprint (SHA256): ...
Notice: Did not receive certificate
Notice: Set up to fetch a certificate
Notice: No certificate found; still waiting
```
*(This is expected behavior as the CA has not signed the certificate yet).*

---

### Step 5.2: Inspect and Sign Certificate on Puppet Server
On the **Management Server**:

List pending certificate requests:
```bash
sudo /opt/puppetlabs/bin/puppetserver ca list
```
Expected output:
```text
Requested Certificates:
    client.ec2.internal   (SHA256)  ...
```

Sign the certificate for `client.ec2.internal`:
```bash
sudo /opt/puppetlabs/bin/puppetserver ca sign --certname client.ec2.internal
```
Expected output:
```text
Successfully signed certificate request for client.ec2.internal
```

---

### Step 5.3: Verify Connection from Client
On the **Managed Client**:
```bash
sudo /opt/puppetlabs/bin/puppet agent -t
```
Expected output:
```text
Info: Downloaded certificate for client.ec2.internal from puppetmaster.ec2.internal
Info: Using configured environment 'production'
Info: Retrieving pluginfacts
Info: Retrieving plugin
Info: Caching catalog for client.ec2.internal
Info: Applying configuration version '...'
Notice: Applied catalog in ... seconds
```

### Step 5.4: Enable and Start Puppet Agent Service
Start the Puppet Agent background daemon on the Client:
```bash
sudo systemctl enable puppet
sudo systemctl start puppet
sudo systemctl status puppet --no-pager
```

---

## 6. Verification and Health Check Commands

| Operation | Command | Run On | Expected Result |
| :--- | :--- | :--- | :--- |
| **Check CA Status** | `sudo puppetserver ca list --all` | Management Server | Lists signed certificates for both `puppetmaster.ec2.internal` and `client.ec2.internal`. |
| **Test Port 8140** | `nc -zv puppetmaster.ec2.internal 8140` | Managed Client | `Connection to puppetmaster.ec2.internal 8140 port [tcp/*] succeeded!` |
| **Manual Dry Run** | `sudo puppet agent -t --noop` | Managed Client | Runs catalog compilation without modifying live system files. |
| **View Agent Log** | `sudo journalctl -u puppet -n 20 --no-pager` | Managed Client | Displays daemon sync cycles every 30 minutes. |

