# ==============================================================================
# Puppet Security Baseline Module: security_baseline
# ==============================================================================
# Main class orchestrating security hardening across SSH, system services,
# critical file permissions, system time synchronization, and kernel sysctl.
# ==============================================================================

class security_baseline (
  Enum['yes', 'no', 'prohibit-password'] $permit_root_login       = 'no',
  Enum['yes', 'no']                     $password_authentication = 'no',
  Integer[1, 10]                        $max_auth_tries          = 4,
  Boolean                               $enforce_auditd          = true,
  Boolean                               $enforce_firewall        = true,
  Boolean                               $enforce_timesyncd       = true,
  Boolean                               $enforce_file_perms      = true,
  Boolean                               $enforce_sysctl          = true,
) {

  # Step 1: Manage SSH Daemon configuration and root login restrictions
  class { 'security_baseline::ssh':
    permit_root_login       => $permit_root_login,
    password_authentication => $password_authentication,
    max_auth_tries          => $max_auth_tries,
  }

  # Step 2: Ensure critical security daemons are running and insecure services disabled
  class { 'security_baseline::services':
    enforce_auditd   => $enforce_auditd,
    enforce_firewall => $enforce_firewall,
  }

  # Step 3: Enforce strict file ownership and permission boundaries
  if $enforce_file_perms {
    class { 'security_baseline::file_permissions': }
  }

  # Step 4: Time synchronization and persistent system logging
  if $enforce_timesyncd {
    class { 'security_baseline::logging_time': }
  }

  # Step 5: Kernel network security hardening via sysctl
  if $enforce_sysctl {
    class { 'security_baseline::sysctl': }
  }

  # Dependency ordering
  Class['security_baseline::file_permissions']
  -> Class['security_baseline::services']
  -> Class['security_baseline::ssh']
}

