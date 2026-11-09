# ==============================================================================
# Class: security_baseline::logging_time
# ==============================================================================
# Ensures network time synchronization via systemd-timesyncd and persistent
# system event logging via rsyslog.
# ==============================================================================

class security_baseline::logging_time {

  # Time synchronization service (systemd-timesyncd)
  service { 'systemd-timesyncd':
    ensure     => running,
    enable     => true,
    hasrestart => true,
    hasstatus  => true,
  }

  # System logging daemon (rsyslog)
  package { 'rsyslog':
    ensure => installed,
  }

  service { 'rsyslog':
    ensure     => running,
    enable     => true,
    hasrestart => true,
    hasstatus  => true,
    require    => Package['rsyslog'],
  }
}

