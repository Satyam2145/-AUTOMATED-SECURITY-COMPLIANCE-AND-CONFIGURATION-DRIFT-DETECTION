# ==============================================================================
# Class: security_baseline::file_permissions
# ==============================================================================
# Enforces strict ownership and permissions on sensitive system credential
# and scheduling files to prevent unauthorized disclosure or tampering.
# ==============================================================================

class security_baseline::file_permissions {

  # Shadow password store (Readable only by root and shadow group)
  file { '/etc/shadow':
    ensure => file,
    owner  => 'root',
    group  => 'shadow',
    mode   => '0640',
  }

  # Group shadow store
  file { '/etc/gshadow':
    ensure => file,
    owner  => 'root',
    group  => 'shadow',
    mode   => '0640',
  }

  # User account database (Publicly readable, writable only by root)
  file { '/etc/passwd':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0644',
  }

  # Group account database
  file { '/etc/group':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0644',
  }

  # System-wide crontab (Root execution only)
  file { '/etc/crontab':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0600',
  }

  # Periodic cron directories
  $cron_dirs = [
    '/etc/cron.hourly',
    '/etc/cron.daily',
    '/etc/cron.weekly',
    '/etc/cron.monthly',
    '/etc/cron.d',
  ]

  file { $cron_dirs:
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0700',
  }
}

