# ==============================================================================
# Class: security_baseline::sysctl
# ==============================================================================
# Configures kernel network parameters to mitigate IP spoofing, packet redirects,
# and ICMP broadcast attacks.
# ==============================================================================

class security_baseline::sysctl {

  file { '/etc/sysctl.d/99-security-baseline.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    source  => 'puppet:///modules/security_baseline/99-security-baseline.conf',
    notify  => Exec['reload_sysctl_security'],
  }

  exec { 'reload_sysctl_security':
    command     => '/sbin/sysctl -p /etc/sysctl.d/99-security-baseline.conf',
    refreshonly => true,
  }
}

