# Test and Execution Evidence Directory

This directory stores visual evidence and verification artifacts for all validation test scenarios defined in the project test plan (`tests/test-plan.md`).

## Evidence Naming Conventions

When capturing screenshots or terminal recordings during testing phases, please use the standardized naming convention:

- `test-01-ec2-connectivity.png` - ICMP / SSH connectivity verification between Management and Client instances.
- `test-02-puppet-cert-agent.png` - Puppet Agent certificate signing and successful initial catalog run.
- `test-03-puppet-baseline-apply.png` - Application of the `security_baseline` module on the managed client.
- `test-04-nagios-initial-dashboard.png` - Nagios Core Web UI showing all hosts and security baseline services in OK state.
- `test-05-drift-injection.png` - Controlled manual modification of a security baseline setting (e.g., SSH PermitRootLogin).
- `test-06-nagios-drift-alert.png` - Nagios Core alerting with WARNING or CRITICAL state following drift detection.
- `test-07-puppet-remediation.png` - Puppet Agent run enforcing approved security state and correcting the drift.
- `test-08-compliance-restored.png` - Bash compliance check returning exit code 0 and Nagios returning to green OK state.

## Guidelines
- Ensure sensitive information (such as AWS Access Key IDs, private IP credentials, or private SSH keys) is blurred or omitted.
- High-resolution PNG formats are preferred for academic and presentation clarity.

