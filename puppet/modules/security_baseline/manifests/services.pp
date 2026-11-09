# ==============================================================================
# Class: security_baseline::services
# ==============================================================================
# Manages essential security daemons and disables unapproved or insecure legacy
# networking services.
# ==============================================================================

class security_baseline::services (
  Boolean $enforce_auditd   = true,
  Boolean $enforce_firewall = true,
) {

  # 1. Linux Audit Daemon (auditd)
  if $enforce_auditd {
    package { 'auditd':
      ensure => installed,
    }

    service { 'auditd':
      ensure     => running,
      enable     => true,
      hasrestart => true,
      hasstatus  => true,
      require    => Package['auditd'],
    }
  }

  # 2. Host Firewall (ufw)
  if $enforce_firewall {
    package { 'ufw':
      ensure => installed,
    }

    service { 'ufw':
      ensure     => running,
      enable     => true,
      hasrestart => true,
      hasstatus  => true,
      require    => Package['ufw'],
    }
  }

  # 3. Disable insecure / legacy services (CIS benchmark recommendations)
  $insecure_packages = [
    'telnet',
    'rsh-client',
    'rsh-server',
    'talk',
    'xinetd',
    'nis',
  ]

  package { $insecure_packages:
    ensure => purged,
  }
}

