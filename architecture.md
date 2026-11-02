# System Architecture & Technical Specifications

**Project:** Automated Security Compliance and Configuration Drift Detection Using Puppet and Nagios on AWS EC2  
**Target Environment:** Amazon Web Services (AWS) VPC / Ubuntu Linux LTS  

---

## 1. High-Level Architectural Overview

The architecture employs a decoupled, multi-node management design consisting of two primary EC2 instances operating within an isolated AWS Virtual Private Cloud (VPC) subnet. The design separates **centralized governance and observability** (Instance 1) from the **workload execution surface** (Instance 2).

```mermaid
flowchart TD
    subgraph ADMIN_TIER["Administrator & Operator Access"]
        Admin["DevOps Engineer / Auditor\n(Admin Workstation)"]
    end

    subgraph AWS_VPC["AWS Virtual Private Cloud (10.0.0.0/16)"]
        subgraph MGMT_INSTANCE["EC2 Instance 1: Management Server (t3.medium)"]
            PuppetServer["Puppet Server\n(Port 8140 / mTLS CA)"]
            NagiosCore["Nagios Core Engine\n(Scheduler & Alerting)"]
            NagiosUI["Nagios Web Interface\n(Apache HTTP / Port 80)"]
            CheckNRPE["check_nrpe Plugin"]
        end

        subgraph CLIENT_INSTANCE["EC2 Instance 2: Managed Client (t3.micro)"]
            PuppetAgent["Puppet Agent\n(State Convergence Engine)"]
            NRPEDaemon["NRPE Daemon\n(Port 5666 / TLS Allowed Hosts)"]
            
            subgraph SECURITY_BASELINE["Security Hardened Surface"]
                SSHConfig["/etc/ssh/sshd_config\n(PermitRootLogin no)"]
                SysServices["Essential Daemons\n(auditd, ufw, timesyncd)"]
                PermCheck["Critical File Permissions\n(/etc/shadow 0640, /etc/passwd 0644)"]
            end

            subgraph COMPLIANCE_SCRIPTS["Custom Compliance Plugins"]
                ScriptSSH["check_ssh_security.sh"]
                ScriptServices["check_services.sh"]
                ScriptPerms["check_file_permissions.sh"]
                ScriptOverall["check_security_baseline.sh"]
            end
        end
    end

    %% Administrative Connections
    Admin -->|SSH Port 22 / Admin IP Only| MGMT_INSTANCE
    Admin -->|SSH Port 22 / Admin IP Only| CLIENT_INSTANCE
    Admin -->|HTTP Port 80 / Admin IP Only| NagiosUI

    %% Internal Management & Monitoring Connections
    PuppetAgent -->|mTLS Pull Catalog / TCP 8140\nPrivate Subnet| PuppetServer
    CheckNRPE -->|Encrypted Remote Checks / TCP 5666\nPrivate Subnet| NRPEDaemon

    %% Internal Client Flow
    PuppetAgent -.->|Enforces Baseline| SECURITY_BASELINE
    NRPEDaemon -->|Executes Probes| COMPLIANCE_SCRIPTS
    COMPLIANCE_SCRIPTS -->|Inspects State & File Modes| SECURITY_BASELINE
    COMPLIANCE_SCRIPTS -->|Returns Exit Code 0-3| NRPEDaemon
    NRPEDaemon -->|Reports Compliance Status| CheckNRPE
    CheckNRPE -->|Updates Service State| NagiosCore
```

---

## 2. Infrastructure & Node Specifications

### 2.1 EC2 Instance 1: Management Server
- **Role:** Centralized authority for configuration management and infrastructure monitoring.
- **Recommended Instance Type:** `t3.medium` (2 vCPU, 4 GiB RAM) to accommodate the JVM footprint of Puppet Server along with Nagios Core and Apache.
- **Operating System:** Ubuntu Server 22.04 / 24.04 LTS.
- **Software Components:**
  - `puppetserver`: Serves as the Puppet Certificate Authority (CA) and compiles catalogs for managed nodes.
  - `nagios`: Core daemon managing monitoring schedules, check dispatch, state retention, and notification pipelines.
  - `nagios-plugins` & `check_nrpe`: Client binary used by Nagios to query remote NRPE daemons.
  - `apache2`: Web server hosting the Nagios Core web console.

### 2.2 EC2 Instance 2: Managed Client
- **Role:** Monitored Linux host undergoing configuration enforcement and security baseline compliance checks.
- **Recommended Instance Type:** `t3.micro` (1 vCPU, 1 GiB RAM) or `t3.small` (for low-cost lab environments).
- **Operating System:** Ubuntu Server 22.04 / 24.04 LTS.
- **Software Components:**
  - `puppet-agent`: Periodically contacts Puppet Server, pulls the compiled catalog, and enforces local system state.
  - `nagios-nrpe-server`: Remote plugin executor daemon listening on TCP port 5666, restricted strictly to accept queries from the Management Server's private IP.
  - Custom POSIX compliance plugins stored in `/usr/local/lib/nagios/plugins/` (or `/usr/lib/nagios/plugins/`).

---

## 3. Network Architecture and Security Groups

To maintain security best practices and prevent unauthorized exposure, **no management or monitoring ports are exposed to the public internet**.

### 3.1 Port Allocation Matrix

| Port | Protocol | Source | Destination | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **22** | TCP | Admin Workstation Public IP (`YOUR_IP/32`) | Management & Client Public IPs | Secure administrative SSH access. |
| **80 / 443** | TCP | Admin Workstation Public IP (`YOUR_IP/32`) | Management Server Public IP | Nagios Core web monitoring dashboard. |
| **8140** | TCP | Managed Client Private IP (`10.0.1.X/32`) | Management Server Private IP | Puppet Server catalog requests and mTLS certificate exchange. |
| **5666** | TCP | Management Server Private IP (`10.0.1.Y/32`) | Managed Client Private IP | Nagios NRPE remote probe execution. |
| **ICMP** | Echo | Management Server Private IP | Managed Client Private IP | Internal host ping / host alive monitoring. |

### 3.2 Security Group Rules

#### Security Group A: `sg-management` (Attached to Management Server)
- **Inbound:**
  - `TCP 22` from `YOUR_IP/32` (Admin SSH).
  - `TCP 80` from `YOUR_IP/32` (Nagios Web Dashboard).
  - `TCP 8140` from `sg-client` (Puppet Agent catalog queries).
- **Outbound:**
  - `TCP 5666` to `sg-client` (NRPE queries).
  - `TCP 80/443` to `0.0.0.0/0` (OS package repositories and security updates).

#### Security Group B: `sg-client` (Attached to Managed Client)
- **Inbound:**
  - `TCP 22` from `YOUR_IP/32` (Admin SSH).
  - `TCP 5666` from `sg-management` (NRPE check queries).
  - `ICMP Echo Request` from `sg-management` (Host alive check).
- **Outbound:**
  - `TCP 8140` to `sg-management` (Puppet Server communication).
  - `TCP 80/443` to `0.0.0.0/0` (OS package repositories).

---

## 4. Communication Workflows

### 4.1 Normal Convergence and Baseline Verification Workflow

```mermaid
sequenceDiagram
    autonumber
    participant A as Puppet Agent (Client)
    participant S as Puppet Server (Mgmt)
    participant N as Nagios Core (Mgmt)
    participant R as NRPE Daemon (Client)
    participant C as Compliance Scripts (Client)
    participant OS as System Configurations (Client)

    Note over A,S: Scheduled or Triggered CM Cycle
    A->>S: Request Catalog (mTLS Auth)
    S-->>A: Return Compiled Security Catalog
    A->>OS: Apply Catalog (Ensure SSH, Perms, Daemons)
    A->>S: Submit Execution Report (0 changes / Compliant)

    Note over N,OS: Continuous Monitoring Cycle (e.g. Every 2 mins)
    N->>R: check_nrpe -H Client_IP -c check_security_baseline
    R->>C: Execute /usr/local/lib/nagios/plugins/check_security_baseline.sh
    C->>OS: Inspect /etc/ssh/sshd_config, file modes, active services
    OS-->>C: Current Values Match Baseline
    C-->>R: Output: "OK - All security controls compliant" (Exit Code 0)
    R-->>N: Status: OK
    Note over N: Nagios Dashboard: Green (OK)
```

---

### 4.2 Configuration Drift Detection and Remediation Sequence

When an unauthorized change occurs (e.g., an ad-hoc modification enables root SSH login or changes sensitive file permissions):

```mermaid
sequenceDiagram
    autonumber
    actor Attacker as Out-of-Band Action / Unauthorized User
    participant OS as System Configurations (Client)
    participant C as Compliance Scripts (Client)
    participant R as NRPE Daemon (Client)
    participant N as Nagios Core (Mgmt)
    actor Admin as DevOps Engineer / Administrator
    participant A as Puppet Agent (Client)
    participant S as Puppet Server (Mgmt)

    Attacker->>OS: Modifies /etc/ssh/sshd_config (PermitRootLogin yes)
    Note over OS: System is now DRIFTED and NON-COMPLIANT

    Note over N,OS: Nagios Scheduled Check Triggers
    N->>R: check_nrpe -H Client_IP -c check_ssh_security
    R->>C: Execute check_ssh_security.sh
    C->>OS: Reads /etc/ssh/sshd_config
    OS-->>C: PermitRootLogin is set to "yes"
    C-->>R: Output: "CRITICAL - PermitRootLogin is set to yes" (Exit Code 2)
    R-->>N: Return State: CRITICAL (Exit 2)
    Note over N: Nagios triggers alert: Red (CRITICAL)

    N-->>Admin: Alert Notification (Dashboard / Log / Email)
    Admin->>Admin: Inspects Root Cause & Verifies Threat

    Note over Admin,A: Remediation Phase
    Admin->>A: Trigger Puppet Agent Enforcement (`sudo puppet agent -t`)
    A->>S: Fetch Golden Security Baseline
    S-->>A: Authoritative Catalog
    A->>OS: Reverts /etc/ssh/sshd_config to 'PermitRootLogin no' & Reloads SSH
    
    Note over N,OS: Verification Cycle
    N->>R: check_nrpe -H Client_IP -c check_ssh_security
    R->>C: Execute check_ssh_security.sh
    C->>OS: Reads /etc/ssh/sshd_config (PermitRootLogin no)
    C-->>R: Output: "OK - SSH configuration compliant" (Exit Code 0)
    R-->>N: Return State: OK (Exit 0)
    Note over N: Alert Cleared: Green (OK)
```

---

## 5. Defense-in-Depth & Architectural Principles

1. **Decoupled Verification:** Configuration management tools possess confirmation bias—they assume that if no manifest was compiled for a setting, it is not drifted. Independent Nagios Bash probes evaluate the live Linux OS kernel and filesystem directly without reading Puppet state files.
2. **Deterministic Exit Codes:** Every compliance probe complies strictly with the Nagios Plugin API standard:
   - `0`: OK (Compliant with security baseline).
   - `1`: WARNING (Non-critical deviation, e.g. service latency or deprecated parameter).
   - `2`: CRITICAL (High-risk security breach, e.g. root login permitted, shadow file world-readable).
   - `3`: UNKNOWN (Missing configuration file, syntax failure, or execution permission error).
3. **Least Privilege Network Isolation:** Puppet Server runs strictly over private IPs. The Nagios web console is restricted to the administrator's CIDR block.
4. **Controlled Remediation Safety:** Automated drift correction is staged with administrative oversight to avoid race conditions or clobbering authorized emergency changes before analysis.

