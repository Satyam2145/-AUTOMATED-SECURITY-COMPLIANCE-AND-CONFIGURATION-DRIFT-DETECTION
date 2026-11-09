# ==============================================================================
# Primary Node Manifest: site.pp
# ==============================================================================
# Defines node classifications and assigns configuration baselines.
# ==============================================================================

# Global defaults
File {
  backup => false,
}

# Default node configuration for unclassified hosts
node default {
  notify { 'unclassified_node':
    message => "Host ${facts['networking']['fqdn']} is connected but has no specific node classification.",
  }
}

# Managed Client Node: Enforce Security Compliance Baseline
node 'client.ec2.internal' {
  notify { 'applying_security_baseline':
    message => "Applying automated security baseline to ${facts['networking']['fqdn']}...",
  }

  class { 'security_baseline':
    permit_root_login       => 'no',
    password_authentication => 'no',
    max_auth_tries          => 4,
    enforce_auditd          => true,
    enforce_firewall        => true,
    enforce_timesyncd       => true,
  }
}

# Management Server Node (Self-managed baseline)
node 'puppetmaster.ec2.internal' {
  class { 'security_baseline':
    permit_root_login       => 'no',
    password_authentication => 'no',
    max_auth_tries          => 4,
    enforce_auditd          => true,
    enforce_firewall        => false, # Keep flexible for Nagios web console
    enforce_timesyncd       => true,
  }
}

