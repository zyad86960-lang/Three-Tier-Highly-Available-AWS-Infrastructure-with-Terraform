# aws-3tier-ha-infra

Production-ready 3-tier AWS infrastructure provisioned with Terraform. Deploys a multi-AZ VPC with public/private subnets, an internet-facing ALB, Apache EC2 instances, Auto Scaling Group, and a private RDS MySQL database — all secured with layered security groups and NAT Gateway routing.

---

## Architecture

```
Internet
    │
    ▼
┌─────────────────────────────────────┐
│     Application Load Balancer       │  ← public subnets (us-east-1a/1b)
│           (lbSG: :80)               │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│         Target Group (HTTP:80)      │
└──────┬──────────────────┬───────────┘
       │                  │
       ▼                  ▼
┌─────────────┐    ┌─────────────┐    ┌─────────────────┐
│ web instance│    │ app instance│    │  Auto Scaling   │
│  us-east-1a │    │  us-east-1b │    │  Group (1–3)    │
│  (Apache)   │    │  (Apache)   │    │                 │
└─────────────┴────┴─────────────┴────┴─────────────────┘
        Private Subnets (webSG)
                 │
                 ▼
┌─────────────────────────────────────┐
│         RDS MySQL 8.0               │  ← private subnets (us-east-1a/1b)
│         (db_sg: :3306 from webSG)   │
└─────────────────────────────────────┘

NAT Gateway (public subnet) → outbound internet for private instances
```

---

## Stack

| Layer | Technology |
|---|---|
| IaC | Terraform |
| Cloud | AWS (us-east-1) |
| Networking | VPC, Public/Private Subnets, IGW, NAT Gateway, Route Tables |
| Compute | EC2 (Amazon Linux 2023), Auto Scaling Group, Launch Configuration |
| Load Balancing | Application Load Balancer, Target Group |
| Database | RDS MySQL 8.0 |
| Security | Security Groups (lbSG, webSG, db_sg) |

---

## Prerequisites

- Terraform `>= 1.5.0`
- AWS CLI configured with a valid profile
- An SSH key pair at `~/.ssh/id_rsa.pub`
- Sufficient IAM permissions (EC2, VPC, RDS, ALB, ASG)

---

## Usage

```bash
# 1. Clone the repo
git clone https://github.com/<your-username>/aws-3tier-ha-infra.git
cd aws-3tier-ha-infra

# 2. Initialize Terraform
terraform init

# 3. Review the plan
terraform plan

# 4. Apply
terraform apply
```

---

## Variables

| Variable | Type | Description | Default |
|---|---|---|---|
| `vpc_cider` | string | VPC CIDR block | `"10.0.0.0/16"` |
| `vpc_name` | string | VPC name tag | `"main-vpc"` |
| `public_subnet` | map(number) | AZ → subnet index for public subnets | see `terraform.tfvars` |
| `private_subnet` | map(number) | AZ → subnet index for private subnets | see `terraform.tfvars` |
| `allowed_ports` | list(number) | Ports opened on webSG | `[22, 80, 443]` |
| `instance_type` | string | EC2 instance type | `"t2.micro"` |

Example `terraform.tfvars`:
```hcl
vpc_cider = "10.0.0.0/16"
vpc_name  = "main-vpc"

public_subnet = {
  "us-east-1a" = 1
  "us-east-1b" = 2
}

private_subnet = {
  "us-east-1a" = 3
  "us-east-1b" = 4
}

allowed_ports = [22, 80, 443]
instance_type = "t2.micro"
```

---

## Security Notes

- EC2 instances live in **private subnets** — not directly reachable from the internet
- Only the ALB is internet-facing; it forwards traffic to instances on port 80
- RDS only accepts connections from `webSG` on port 3306
- All EBS root volumes are encrypted
- ⚠️ DB credentials are currently hardcoded — move to AWS Secrets Manager before production use

---

## Destroy

```bash
terraform destroy
```

---

## License

MIT
