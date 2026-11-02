# Project Synopsis: Automated Security Compliance and Configuration Drift Detection Using Puppet and Nagios on AWS EC2

**Author:** Satyam Sharma  
**Academic Level:** Final-Year Engineering / Cloud DevOps Capstone  
**Target Platform:** Amazon Web Services (AWS EC2), Ubuntu 22.04 / 24.04 LTS  
**Primary Technologies:** Puppet Server & Agent, Nagios Core, NRPE, POSIX Bash, Git, AWS VPC  

---

## Abstract

Modern cloud environments rely on rapid, scalable infrastructure provisioning. However, as systems evolve, cloud instances frequently suffer from **configuration drift**—unauthorized, manual, or accidental changes that cause the runtime state of a machine to deviate from its approved operational and security baseline. While configuration management tools like Puppet are designed to declare and enforce desired states, they often operate on scheduled polling cycles (e.g., every 30 minutes), creating a significant temporal blind spot where security vulnerabilities, such as re-enabled root SSH access or altered file permissions, may persist unnoticed.

This project designs, implements, and evaluates an automated, resilient, and closed-loop security compliance and configuration drift detection architecture on AWS EC2. Utilizing a multi-tier design with Ubuntu Linux instances, the system integrates **Puppet Server** for declarative configuration management and **Nagios Core** with custom Nagios Remote Plugin Executor (NRPE) compliance probes for independent, near-real-time drift detection. The project establishes an auditable security baseline adhering to standard hardening benchmarks (SSH hardening, permission integrity on critical system files, mandatory security daemon execution, and time synchronization). A controlled remediation loop demonstrates end-to-end detection, alerting, and idempotent restoration of the compliant state, providing an academic and practical model for cloud infrastructure governance.

---

## 1. Introduction and Background

In enterprise cloud computing, infrastructure stability and cybersecurity are intrinsically tied to configuration consistency. The rapid adoption of cloud infrastructure-as-a-service (IaaS), such as AWS EC2, enables high operational agility but simultaneously amplifies the attack surface if systems are improperly maintained.

Two critical paradigms govern cloud systems administration:
1. **Configuration Management (CM):** Declaratively defining what a system *should* look like (desired state) and continuously converging local states toward that declaration (e.g., Puppet, Ansible, Chef).
2. **Infrastructure Monitoring and Observability:** Continuously querying system health, service availability, and runtime parameters to generate alerts when metrics breach defined thresholds (e.g., Nagios Core, Prometheus, Zabbix).

Historically, organizations have treated these two disciplines as isolated silos. This separation introduces a fundamental vulnerability: **Configuration Drift**.

```
[Approved Baseline] ---> (Ad-hoc manual edit / zero-day breach) ---> [Drifted Unsafe State]
                                                                            │
      ┌─────────────────────────────────────────────────────────────────────┘
      ▼
[Security Vulnerability Window: Unmonitored until next CM cycle or security audit]
```

---

## 2. Problem Statement

Configuration drift poses severe operational and security risks:
- **Security Vulnerability Window:** If an administrator or malicious actor modifies `/etc/ssh/sshd_config` to allow `PermitRootLogin yes`, or disables a firewall service (`ufw`), a standard configuration management tool running once per hour leaves a 59-minute window of exposure.
- **Out-of-Band Changes:** Manual hotfixes applied directly via SSH bypass version control and code review pipelines, creating undocumented discrepancies across server fleets.
- **Lack of Independent Verification:** Relying solely on a configuration management tool's internal self-reporting introduces a single point of failure; if the Puppet Agent service crashes, stops communicating, or encounters a compilation error, drift remains entirely invisible.
- **Compliance and Audit Failure:** Frameworks such as CIS (Center for Internet Security), ISO/IEC 27001, and SOC 2 require continuous evidence of compliance and tamper-evident configuration controls.

Therefore, an academic and engineering solution is required to couple **declarative state enforcement** with **independent, out-of-band monitoring and immediate drift alerting**.

---

## 3. Project Objectives

The primary engineering objectives of this project are:

1. **Deploy Reproducible Cloud Infrastructure:** Provision a secure, low-cost AWS EC2 multi-node environment (Management Server and Managed Client) within an isolated Virtual Private Cloud (VPC) subnet utilizing least-privilege security groups and private IP communication.
2. **Establish a Hardened Security Baseline:** Formulate a reusable, modular Puppet manifest (`security_baseline`) that enforces critical Linux security standards:
   - Disabling remote SSH root login (`PermitRootLogin no`).
   - Restricting authentication mechanisms according to lab policy.
   - Restricting file permissions on sensitive security assets (`/etc/shadow`, `/etc/passwd`, `/etc/ssh/sshd_config`).
   - Enforcing execution of essential security and operational services (`auditd`, `ufw`, `systemd-timesyncd`).
   - Maintaining system time synchronization and localized logging.
3. **Implement Independent Compliance Probes:** Develop standalone POSIX Bash compliance inspection plugins adhering to official Nagios Plugin API return codes (0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN).
4. **Configure Centralized Real-Time Monitoring:** Implement Nagios Core 4.x with NRPE on the Management Server to poll host availability, resource utilization, and compliance probes on remote clients.
5. **Demonstrate Closed-Loop Drift Remediation:** Simulate controlled security configuration drift in a lab environment, capture the real-time alerting workflow in Nagios, and validate the automated or admin-triggered convergence back to compliance via Puppet.
6. **Provide Empirical Test Evidence:** Document an end-to-end 8-stage verification test suite with reproducible terminal inputs, expected outputs, and audit logs.

---

## 4. Scope and Limitations

### In-Scope
- Ubuntu 22.04 / 24.04 LTS operating systems running on AWS EC2 (`t3.medium` for Puppet Server, `t3.micro` for Managed Client).
- Puppet Server 7.x/8.x with TLS mutual certificate authentication.
- Nagios Core 4.x built and configured with custom command plugins and NRPE v4.
- POSIX-compliant shell scripts designed for minimal dependencies and deterministic exit codes.
- Version control tracking via Git and GitHub.

### Out-of-Scope
- Proprietary enterprise monitoring suites (Splunk, Datadog).
- Multi-cloud federation (Azure, Google Cloud Platform).
- Complex container orchestration (Kubernetes/EKS), as the focus is operating system configuration compliance.

---

## 5. Technology Stack Summary

| Layer | Technology | Role & Justification |
| :--- | :--- | :--- |
| **Cloud Infrastructure** | AWS EC2 (VPC, Security Groups, IAM) | Provides scalable, isolated compute instances with enterprise network controls. |
| **Operating System** | Ubuntu Linux LTS | Enterprise-grade, stable Debian-based distribution with standard systemd architecture. |
| **Configuration Management** | Puppet Server & Puppet Agent | Declarative, idempotent state management utilizing master-agent mTLS architecture. |
| **Monitoring & Alerting** | Nagios Core | Proven, low-latency, modular infrastructure monitoring engine. |
| **Agent Communication** | NRPE (Nagios Remote Plugin Executor) | Secure protocol for executing local check plugins on remote Linux instances. |
| **Compliance Logic** | Custom POSIX Bash | Lightweight, zero-external-dependency security audit scripts. |
| **Version Control** | Git & GitHub | Academic code provenance, version tracking, and documentation hosting. |

---

## 6. Expected Academic and Practical Outcomes

Upon successful execution, this project delivers:
1. A fully documented, production-aligned infrastructure baseline for Linux servers in cloud environments.
2. A dual-control governance architecture proving that configuration management and active monitoring form a synergistic defense against configuration drift.
3. A transparent testing methodology demonstrating empirical detection of security policy violations within minutes of occurrence.

