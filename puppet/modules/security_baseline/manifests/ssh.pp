# ==============================================================================
# Class: security_baseline::ssh
# ==============================================================================
# Hardens OpenSSH server settings:
# - Disables root login via SSH (PermitRootLogin no)
# - Restricts password authentication according to lab policy
# - Sets authentication retry limits and idle timeouts
# - Validates syntax before restarting sshd to prevent lockout
# ==============================================================================

class security_baseline::ssh (
  Enum['yes', 'no', 'prohibit-password'] $permit_root_login       = 'no',
  Enum['yes', 'no']                     $password_authentication = 'no',
  Integer[1, 10]                        $max_auth_tries          = 4,
) {

  # Ensure OpenSSH server package is installed
  package { 'openssh-server':
    ensure => present,
  }

  # Ensure SSH service is running and enabled
  # On Ubuntu LTS, the systemd service name is 'ssh'
  service { 'ssh':
    ensure     => running,
    enable     => true,
    hasrestart => true,
    hasstatus  => true,
    require    => Package['openssh-server'],
  }

  # Deploy hardened sshd_config from template/content
  # Uses validate_cmd to test sshd configuration integrity before activating
  file { '/etc/ssh/sshd_config':
    ensure       => file,
    owner        => 'root',
    group        => 'root',
    mode         => '0600',
    content      => epp('security_baseline/sshd_config.epp', {
      'permit_root_login'       => $permit_root_login,
      'password_authentication' => $password_authentication,
      'max_auth_tries'          => $max_auth_tries,
    }),
    validate_cmd => '/usr/sbin/sshd -t -f %',
    notify       => Service['ssh'],
    require      => Package['openssh-server'],
  }
}

