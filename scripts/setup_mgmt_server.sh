#!/usr/bin/env bash
# ==============================================================================
# Script: setup_mgmt_server.sh
# Purpose: Automated bootstrap script for EC2 Instance 1 (Management Server).
# Installs: Puppet Server 7.x, Nagios Core 4.4.x, Nagios Plugins, check_nrpe.
# Target OS: Ubuntu 22.04 LTS (Jammy)
# ==============================================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] This script must be run as root (use sudo)."
   exit 1
fi

echo "=============================================================================="
echo " Starting Management Server Bootstrap: Puppet Server & Nagios Core"
echo "=============================================================================="

# 1. Hostname configuration
echo "[1/7] Setting system hostname..."
hostnamectl set-hostname puppetmaster.ec2.internal

# 2. Update and install base build dependencies
echo "[2/7] Installing base system dependencies..."
apt-get update -y
apt-get install -y autoconf gcc libc6 make wget unzip apache2 php \
    libapache2-mod-php libgd-dev libssl-dev bc gawk dc build-essential \
    snmp libnet-snmp-perl gettext curl net-tools

# 3. Install Puppet Server
echo "[3/7] Installing Puppet Server..."
cd /tmp
if [[ ! -f puppet7-release-jammy.deb ]]; then
    wget https://apt.puppet.com/puppet7-release-jammy.deb
    dpkg -i puppet7-release-jammy.deb
    apt-get update -y
fi

apt-get install -y puppetserver

# Configure JVM heap size for t3.medium (1.5 GiB)
sed -i 's/-Xms2g -Xmx2g/-Xms1536m -Xmx1536m/' /etc/default/puppetserver

# Set up PATH for Puppet
echo 'export PATH=/opt/puppetlabs/bin:$PATH' > /etc/profile.d/puppet.sh
export PATH=/opt/puppetlabs/bin:$PATH

# Puppet Server configuration
cat <<EOF > /etc/puppetlabs/puppet/puppet.conf
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
EOF

# Initialize CA and start Puppet Server
echo "[INFO] Initializing Puppet Server CA and starting daemon..."
/opt/puppetlabs/bin/puppetserver ca setup || true
systemctl daemon-reload
systemctl enable puppetserver
systemctl restart puppetserver

# 4. Compile and Install Nagios Core
echo "[4/7] Compiling and installing Nagios Core 4.4.14..."
cd /tmp
if [[ ! -f nagioscore.tar.gz ]]; then
    wget -O nagioscore.tar.gz https://github.com/NagiosEnterprises/nagioscore/archive/nagios-4.4.14.tar.gz
fi
tar -xzf nagioscore.tar.gz
cd nagioscore-nagios-4.4.14/

./configure --with-httpd-conf=/etc/apache2/sites-enabled
make all
make install-groups-users
usermod -a -G nagios www-data
make install
make install-daemoninit
make install-commandmode
make install-config
make install-webconf

# Enable Apache modules
a2enmod rewrite cgi

# Default admin password for web console
echo "[INFO] Creating nagiosadmin user for Web UI (password: DevopsAdmin2026!)..."
htpasswd -b -c /usr/local/nagios/etc/htpasswd.users nagiosadmin DevopsAdmin2026!
systemctl restart apache2

# 5. Compile and Install Nagios Plugins
echo "[5/7] Compiling Nagios Plugins 2.4.6..."
cd /tmp
if [[ ! -f nagios-plugins.tar.gz ]]; then
    wget --no-check-certificate -O nagios-plugins.tar.gz https://github.com/nagios-plugins/nagios-plugins/releases/download/release-2.4.6/nagios-plugins-2.4.6.tar.gz
fi
tar -xzf nagios-plugins.tar.gz
cd nagios-plugins-2.4.6/
./configure
make
make install

# 6. Compile and Install check_nrpe Plugin
echo "[6/7] Compiling check_nrpe plugin..."
cd /tmp
if [[ ! -f nrpe-4.1.0.tar.gz ]]; then
    wget https://github.com/NagiosEnterprises/nrpe/releases/download/nrpe-4.1.0/nrpe-4.1.0.tar.gz
fi
tar -xzf nrpe-4.1.0.tar.gz
cd nrpe-4.1.0/
./configure --enable-ssl
make check_nrpe
cp src/check_nrpe /usr/local/nagios/libexec/
chmod 755 /usr/local/nagios/libexec/check_nrpe

# 7. Deploy Custom Nagios Configuration
echo "[7/7] Deploying custom Nagios monitoring configurations..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

mkdir -p /usr/local/nagios/etc/devops
cp "$REPO_DIR/nagios/hosts.cfg" /usr/local/nagios/etc/devops/
cp "$REPO_DIR/nagios/services.cfg" /usr/local/nagios/etc/devops/
cp "$REPO_DIR/nagios/commands.cfg" /usr/local/nagios/etc/devops/

if ! grep -q "cfg_file=/usr/local/nagios/etc/devops/hosts.cfg" /usr/local/nagios/etc/nagios.cfg; then
    cat <<EOF >> /usr/local/nagios/etc/nagios.cfg

# DevOps Project Monitoring Definitions
cfg_file=/usr/local/nagios/etc/devops/commands.cfg
cfg_file=/usr/local/nagios/etc/devops/hosts.cfg
cfg_file=/usr/local/nagios/etc/devops/services.cfg
EOF
fi

# Validate and start Nagios
/usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg
systemctl enable nagios
systemctl restart nagios

echo "=============================================================================="
echo " Management Server Bootstrap Complete!"
echo " - Puppet Server listening on TCP 8140"
echo " - Nagios Core Web UI: http://$(curl -s https://checkip.amazonaws.com || echo '<PUBLIC_IP>')/nagios/"
echo "   User: nagiosadmin | Password: DevopsAdmin2026!"
echo "=============================================================================="

