#!/usr/bin/env bash
# ==============================================================================
# Script: setup_client_node.sh
# Purpose: Automated bootstrap script for EC2 Instance 2 (Managed Client Node).
# Installs: Puppet Agent 7.x, nagios-nrpe-server, compliance check probes.
# Target OS: Ubuntu 22.04 LTS (Jammy)
# ==============================================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] This script must be run as root (use sudo)."
   exit 1
fi

echo "=============================================================================="
echo " Starting Managed Client Node Bootstrap: Puppet Agent & NRPE"
echo "=============================================================================="

# 1. Hostname configuration
echo "[1/5] Setting system hostname..."
hostnamectl set-hostname client.ec2.internal

# 2. Update and install Puppet Agent
echo "[2/5] Installing Puppet Agent..."
cd /tmp
if [[ ! -f puppet7-release-jammy.deb ]]; then
    wget https://apt.puppet.com/puppet7-release-jammy.deb
    dpkg -i puppet7-release-jammy.deb
    apt-get update -y
fi

apt-get install -y puppet-agent

echo 'export PATH=/opt/puppetlabs/bin:$PATH' > /etc/profile.d/puppet.sh
export PATH=/opt/puppetlabs/bin:$PATH

cat <<EOF > /etc/puppetlabs/puppet/puppet.conf
[main]
certname = client.ec2.internal
server = puppetmaster.ec2.internal
environment = production
runinterval = 30m
EOF

# 3. Install NRPE Daemon and Nagios Plugins
echo "[3/5] Installing nagios-nrpe-server and nagios-plugins..."
apt-get install -y nagios-nrpe-server nagios-plugins

# 4. Deploy Custom Compliance Check Plugins
echo "[4/5] Deploying custom compliance audit probes..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p /usr/local/lib/nagios/plugins
cp "$SCRIPT_DIR"/check_*.sh /usr/local/lib/nagios/plugins/
chmod +x /usr/local/lib/nagios/plugins/*.sh

# Deploy memory check plugin
cat << "EOF" > /usr/local/lib/nagios/plugins/check_mem.sh
#!/bin/bash
TOTAL=$(free -m | awk '/^Mem:/ {print $2}')
USED=$(free -m | awk '/^Mem:/ {print $3}')
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
EOF
chmod +x /usr/local/lib/nagios/plugins/check_mem.sh
chown -R root:nagios /usr/local/lib/nagios/plugins
chmod 750 /usr/local/lib/nagios/plugins

# 5. Configure NRPE Daemon
echo "[5/5] Configuring NRPE allowed hosts and command bindings..."
MGMT_IP="10.0.1.50" # Replace if using custom IP
if grep -q "puppetmaster.ec2.internal" /etc/hosts; then
    RESOLVED_IP=$(awk '/puppetmaster/ {print $1; exit}' /etc/hosts)
    [[ -n "$RESOLVED_IP" ]] && MGMT_IP="$RESOLVED_IP"
fi

sed -i "s/^allowed_hosts=.*/allowed_hosts=127.0.0.1,::1,${MGMT_IP}/" /etc/nagios/nrpe.cfg

# Append custom check commands if not already registered
if ! grep -q "check_ssh_security" /etc/nagios/nrpe.cfg; then
    cat << "EOF" >> /etc/nagios/nrpe.cfg

# DevOps Project Custom NRPE Command Bindings
command[check_load]=/usr/lib/nagios/plugins/check_load -r -w 5.0,4.0,3.0 -c 10.0,8.0,6.0
command[check_disk]=/usr/lib/nagios/plugins/check_disk -w 20% -c 10% -p /
command[check_mem]=/usr/local/lib/nagios/plugins/check_mem.sh
command[check_puppet_agent]=/usr/lib/nagios/plugins/check_procs -c 1:1 -C puppet
command[check_ssh_security]=/usr/local/lib/nagios/plugins/check_ssh_security.sh
command[check_services]=/usr/local/lib/nagios/plugins/check_services.sh
command[check_file_permissions]=/usr/local/lib/nagios/plugins/check_file_permissions.sh
command[check_security_baseline]=/usr/local/lib/nagios/plugins/check_security_baseline.sh
EOF
fi

# Scoped sudoers permission for nagios user
cat <<EOF > /etc/sudoers.d/nagios_compliance
nagios ALL=(root) NOPASSWD: /usr/local/lib/nagios/plugins/check_*.sh
EOF
chmod 0440 /etc/sudoers.d/nagios_compliance

# Restart services
systemctl daemon-reload
systemctl enable nagios-nrpe-server
systemctl restart nagios-nrpe-server

echo "=============================================================================="
echo " Managed Client Bootstrap Complete!"
echo " - NRPE listening on port 5666 (Authorized host: $MGMT_IP)"
echo " - Initializing Puppet Agent certificate request..."
echo "=============================================================================="
/opt/puppetlabs/bin/puppet agent -t || true
echo "[INFO] If this is the initial run, please sign the cert on Puppet Server:"
echo "       sudo puppetserver ca sign --certname client.ec2.internal"

