# AWS EC2 Infrastructure Setup Guide

**Project:** Automated Security Compliance and Configuration Drift Detection Using Puppet and Nagios on AWS EC2  
**Target Architecture:** Multi-node AWS Virtual Private Cloud (VPC)  
**Operating System:** Ubuntu Server 22.04 / 24.04 LTS  

---

## 1. Overview and Sizing Specifications

To achieve an authentic enterprise DevOps architecture while minimizing cloud costs for an academic lab, this project utilizes two EC2 instances deployed within the same AWS Region and Availability Zone.

| Parameter | Management Server (Node 1) | Managed Client (Node 2) |
| :--- | :--- | :--- |
| **Instance Name** | `sec-compliance-mgmt` | `sec-compliance-client` |
| **Hostname** | `puppetmaster.ec2.internal` | `client.ec2.internal` |
| **Operating System** | Ubuntu Server 22.04 LTS (HVM) | Ubuntu Server 22.04 LTS (HVM) |
| **Architecture** | 64-bit (x86_64) | 64-bit (x86_64) |
| **Instance Type** | `t3.medium` (2 vCPU, 4 GiB RAM) | `t3.micro` (1 vCPU, 1 GiB RAM) |
| **Storage (EBS)** | 30 GiB General Purpose SSD (gp3) | 20 GiB General Purpose SSD (gp3) |
| **Primary Workloads** | Puppet Server 7.x/8.x, Nagios Core 4.x, Apache2 | Puppet Agent, NRPE Daemon, Compliance Probes |
| **Estimated Cost** | ~\$0.0416 / hour (~\$0.33 for an 8-hour lab) | Free Tier eligible (or ~\$0.0104 / hour) |

> [!IMPORTANT]
> **Why `t3.medium` for Management Server?**  
> Puppet Server runs on the Java Virtual Machine (JVM). Its default heap size is 2 GiB. Running Puppet Server alongside Nagios Core and Apache on an instance with less than 4 GiB of RAM (such as `t3.micro` or `t3.small`) will trigger the Linux Out-Of-Memory (OOM) killer.

---

## 2. Security Group Design (Least-Privilege)

To prevent exposure to brute-force attacks and unauthorized access, **never open ports to `0.0.0.0/0` except where strictly necessary**.

### 2.1 Security Group 1: `sg-management` (Attached to Management Server)

- **Inbound Rules:**

| Type | Protocol | Port Range | Source | Justification |
| :--- | :--- | :--- | :--- | :--- |
| SSH | TCP | `22` | `YOUR_IP/32` | Administrative SSH terminal access. |
| HTTP | TCP | `80` | `YOUR_IP/32` | Nagios Core web monitoring dashboard. |
| Custom TCP | TCP | `8140` | `sg-client` (or Client Private IP) | Puppet Agent catalog requests & mTLS cert exchange. |
| All ICMP | ICMP | All | `sg-client` (or Client Private IP) | Internal network diagnostic ping between nodes. |

- **Outbound Rules:**

| Type | Protocol | Port Range | Destination | Justification |
| :--- | :--- | :--- | :--- | :--- |
| Custom TCP | TCP | `5666` | `sg-client` (or Client Private IP) | Nagios `check_nrpe` remote queries to Client. |
| HTTPS | TCP | `443` | `0.0.0.0/0` | Package repository downloads (`apt-get`). |
| HTTP | TCP | `80` | `0.0.0.0/0` | Canonical Ubuntu mirror downloads. |
| All ICMP | ICMP | All | `sg-client` | Host alive checking. |

---

### 2.2 Security Group 2: `sg-client` (Attached to Managed Client)

- **Inbound Rules:**

| Type | Protocol | Port Range | Source | Justification |
| :--- | :--- | :--- | :--- | :--- |
| SSH | TCP | `22` | `YOUR_IP/32` | Direct administrative SSH terminal access. |
| Custom TCP | TCP | `5666` | `sg-management` (or Mgmt Private IP) | NRPE daemon listening for Nagios queries. |
| All ICMP | ICMP | All | `sg-management` (or Mgmt Private IP) | Nagios ping check (`check_ping` / host status). |

- **Outbound Rules:**

| Type | Protocol | Port Range | Destination | Justification |
| :--- | :--- | :--- | :--- | :--- |
| Custom TCP | TCP | `8140` | `sg-management` (or Mgmt Private IP) | Outbound connection to Puppet Master port 8140. |
| HTTPS | TCP | `443` | `0.0.0.0/0` | Ubuntu package updates. |
| HTTP | TCP | `80` | `0.0.0.0/0` | Package mirrors. |

---

## 3. Step-by-Step Provisioning via AWS Management Console

### Step 3.1: Generate or Select an SSH Key Pair
1. Open the [AWS EC2 Console](https://console.aws.amazon.com/ec2/).
2. In the navigation pane under **Network & Security**, select **Key Pairs**.
3. Click **Create key pair**.
4. Name: `devops-sec-key`.
5. Key pair type: **RSA** or **ED25519**.
6. Private key file format: `.pem` (for OpenSSH / macOS / Linux / Windows PowerShell).
7. Click **Create key pair** and store the downloaded `devops-sec-key.pem` safely.
8. On your local machine, restrict key file permissions:
   ```bash
   # On Linux / macOS / WSL:
   chmod 400 devops-sec-key.pem

   # On Windows PowerShell (removes inheritance and restricts access to current user):
   icacls.exe devops-sec-key.pem /reset
   icacls.exe devops-sec-key.pem /grant:r "$($env:USERNAME):(R)"
   icacls.exe devops-sec-key.pem /inheritance:r
   ```

---

### Step 3.2: Create Security Groups
1. Under **Network & Security**, click **Security Groups** -> **Create security group**.
2. **First Security Group (Management):**
   - Name: `sg-management`
   - Description: `Security group for Puppet Master and Nagios Core`
   - Inbound rules:
     - SSH (22): Source -> **My IP** (`YOUR_IP/32`).
     - HTTP (80): Source -> **My IP** (`YOUR_IP/32`).
3. **Second Security Group (Client):**
   - Name: `sg-client`
   - Description: `Security group for Managed Puppet Client with NRPE`
   - Inbound rules:
     - SSH (22): Source -> **My IP** (`YOUR_IP/32`).
     - Custom TCP (5666): Source -> Select `sg-management`.
     - All ICMP - IPv4: Source -> Select `sg-management`.
4. Return to `sg-management` -> **Edit inbound rules**:
   - Add Custom TCP (8140): Source -> Select `sg-client`.
   - Add All ICMP - IPv4: Source -> Select `sg-client`.

---

### Step 3.3: Launch Instance 1 (Management Server)
1. In the EC2 Console, click **Launch instances**.
2. **Name:** `sec-compliance-mgmt`.
3. **Application and OS Images:** Ubuntu Server 22.04 LTS (64-bit x86).
4. **Instance type:** `t3.medium`.
5. **Key pair:** Select `devops-sec-key`.
6. **Network settings:**
   - Firewall (security groups): Select existing security group -> `sg-management`.
   - Auto-assign public IP: **Enable**.
7. **Configure storage:** 30 GiB gp3.
8. Click **Launch instance**.

---

### Step 3.4: Launch Instance 2 (Managed Client)
1. Click **Launch instances**.
2. **Name:** `sec-compliance-client`.
3. **Application and OS Images:** Ubuntu Server 22.04 LTS (64-bit x86).
4. **Instance type:** `t3.micro` (or `t3.small`).
5. **Key pair:** Select `devops-sec-key`.
6. **Network settings:**
   - Subnet: **Same VPC Subnet as Instance 1** (ensures low-latency private IP routing).
   - Firewall (security groups): Select existing security group -> `sg-client`.
   - Auto-assign public IP: **Enable**.
7. **Configure storage:** 20 GiB gp3.
8. Click **Launch instance**.

---

## 4. Alternative: Automated Provisioning via AWS CLI

If you prefer deploying via the AWS CLI from your local terminal:

```bash
# Set your local variables
REGION="us-east-1"
KEY_NAME="devops-sec-key"
MY_IP="$(curl -s https://checkip.amazonaws.com)/32"
UBUNTU_AMI="ami-0c7217cdde317cfec" # Replace with latest Ubuntu 22.04 AMI in your region
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text --region $REGION)
SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[0].SubnetId" --output text --region $REGION)

# 1. Create Security Groups
SG_MGMT=$(aws ec2 create-security-group --group-name "sg-management" --description "Puppet Master and Nagios" --vpc-id $VPC_ID --output text --query "GroupId" --region $REGION)
SG_CLIENT=$(aws ec2 create-security-group --group-name "sg-client" --description "Managed Client" --vpc-id $VPC_ID --output text --query "GroupId" --region $REGION)

# 2. Authorize Inbound Rules
aws ec2 authorize-security-group-ingress --group-id $SG_MGMT --protocol tcp --port 22 --cidr $MY_IP --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_MGMT --protocol tcp --port 80 --cidr $MY_IP --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_MGMT --protocol tcp --port 8140 --source-group $SG_CLIENT --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_MGMT --protocol icmp --port -1 --source-group $SG_CLIENT --region $REGION

aws ec2 authorize-security-group-ingress --group-id $SG_CLIENT --protocol tcp --port 22 --cidr $MY_IP --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_CLIENT --protocol tcp --port 5666 --source-group $SG_MGMT --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_CLIENT --protocol icmp --port -1 --source-group $SG_MGMT --region $REGION

# 3. Launch Management Instance (t3.medium)
aws ec2 run-instances \
    --image-id $UBUNTU_AMI \
    --instance-type t3.medium \
    --key-name $KEY_NAME \
    --security-group-ids $SG_MGMT \
    --subnet-id $SUBNET_ID \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":30,"VolumeType":"gp3"}}]' \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=sec-compliance-mgmt}]' \
    --region $REGION

# 4. Launch Client Instance (t3.micro)
aws ec2 run-instances \
    --image-id $UBUNTU_AMI \
    --instance-type t3.micro \
    --key-name $KEY_NAME \
    --security-group-ids $SG_CLIENT \
    --subnet-id $SUBNET_ID \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20,"VolumeType":"gp3"}}]' \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=sec-compliance-client}]' \
    --region $REGION
```

---

## 5. Post-Launch Hostname and Networking Configuration

Once instances are in the `running` state, retrieve their **Private IPs** from the EC2 Console.

Assume:
- Management Server Private IP: `10.0.1.50` (Public IP: `54.X.X.50`)
- Managed Client Private IP: `10.0.1.60` (Public IP: `54.X.X.60`)

### 5.1 Configure Management Server Node
Connect via SSH:
```bash
ssh -i devops-sec-key.pem ubuntu@54.X.X.50
```

Set the hostname:
```bash
sudo hostnamectl set-hostname puppetmaster.ec2.internal
```

Add internal DNS mappings to `/etc/hosts`:
```bash
sudo bash -c 'cat <<EOF >> /etc/hosts
10.0.1.50   puppetmaster.ec2.internal puppetmaster puppet
10.0.1.60   client.ec2.internal client
EOF'
```

Verify local resolution:
```bash
ping -c 2 puppetmaster.ec2.internal
```

---

### 5.2 Configure Managed Client Node
Connect via SSH:
```bash
ssh -i devops-sec-key.pem ubuntu@54.X.X.60
```

Set the hostname:
```bash
sudo hostnamectl set-hostname client.ec2.internal
```

Add internal DNS mappings to `/etc/hosts`:
```bash
sudo bash -c 'cat <<EOF >> /etc/hosts
10.0.1.50   puppetmaster.ec2.internal puppetmaster puppet
10.0.1.60   client.ec2.internal client
EOF'
```

Verify internal private connectivity to the Puppet Master:
```bash
ping -c 2 puppetmaster.ec2.internal
```

---

## 6. AWS Cost Management and Charge Avoidance

To conduct this project with minimal expenditure:

1. **Stop Instances When Inactive:**  
   When not actively testing or recording demonstrations, stop the instances. Stopped instances do not incur compute charges (only a few cents per month for EBS storage).
   ```bash
   # Stop instances
   aws ec2 stop-instances --instance-ids <MGMT_INSTANCE_ID> <CLIENT_INSTANCE_ID>

   # Restart when resuming lab
   aws ec2 start-instances --instance-ids <MGMT_INSTANCE_ID> <CLIENT_INSTANCE_ID>
   ```
   > [!NOTE]  
   > Stopping an EC2 instance without an Elastic IP will change its Public IP upon restart, but its **Private IP remains persistent**. Puppet and Nagios communicate entirely over Private IPs, so internal operations remain unaffected!

2. **Setup AWS Zero-Spend / Low-Spend Budget:**  
   In the AWS Management Console, navigate to **AWS Budgets** -> **Create budget** -> **Cost budget** -> set target to **\$5.00/month** with email alerts triggered at 80% and 100%.

3. **Complete Teardown (Post-Project Completion):**  
   After completing all testing and capturing evidence:
   ```bash
   aws ec2 terminate-instances --instance-ids <MGMT_INSTANCE_ID> <CLIENT_INSTANCE_ID>
   aws ec2 delete-security-group --group-id $SG_MGMT
   aws ec2 delete-security-group --group-id $SG_CLIENT
   ```

