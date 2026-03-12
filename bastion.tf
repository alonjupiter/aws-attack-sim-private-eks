# Bastion Host for Managing Private EKS Cluster
# Created in stage1, used to deploy stage2 resources

locals {
  create_bastion = var.create_bastion_host && (var.deployment_stage == "stage1" || var.deployment_stage == "all")
}

# Data source for latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security group for bastion host
resource "aws_security_group" "bastion" {
  count       = local.create_bastion ? 1 : 0
  name        = "${local.standard_prefix}-bastion-sg"
  description = "Security group for bastion host to manage private EKS cluster"
  vpc_id      = local.vpc_id

  # No inbound access needed - using SSM Session Manager only!

  # Allow HTTPS to VPC endpoints
  egress {
    description = "HTTPS to VPC endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  # Allow HTTPS to internet (for downloading packages via NAT Gateway)
  egress {
    description = "HTTPS to internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP to internet (for yum repositories)
  egress {
    description = "HTTP to internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow bastion to communicate with Selenium Grid
  egress {
    description = "Allow bastion to communicate with Selenium Grid"
    from_port   = 24444
    to_port     = 24444
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.tags,
    {
      Name = "${local.standard_prefix}-bastion-sg"
    }
  )

  depends_on = [module.vpc]
}

# IAM role for bastion host
resource "aws_iam_role" "bastion" {
  count = local.create_bastion ? 1 : 0
  name  = "${local.standard_prefix}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

# Attach SSM policy for Session Manager access (no SSH key needed!)
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  count      = local.create_bastion ? 1 : 0
  role       = aws_iam_role.bastion[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach policies for Terraform operations
resource "aws_iam_role_policy_attachment" "bastion_ec2" {
  count      = local.create_bastion ? 1 : 0
  role       = aws_iam_role.bastion[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "bastion_eks" {
  count      = local.create_bastion ? 1 : 0
  role       = aws_iam_role.bastion[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "bastion_iam" {
  count      = local.create_bastion ? 1 : 0
  role       = aws_iam_role.bastion[0].name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}

resource "aws_iam_role_policy_attachment" "bastion_vpc" {
  count      = local.create_bastion ? 1 : 0
  role       = aws_iam_role.bastion[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonVPCFullAccess"
}

# Attach SSM Full Access for parameter management
resource "aws_iam_role_policy_attachment" "bastion_ssm_full" {
  count      = local.create_bastion ? 1 : 0
  role       = aws_iam_role.bastion[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}

# Additional permissions for Stage 2 deployment (EKS, KMS, Logs)
resource "aws_iam_role_policy" "bastion_additional" {
  count = local.create_bastion ? 1 : 0
  name  = "${local.standard_prefix}-bastion-additional-policy"
  role  = aws_iam_role.bastion[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# S3 access policy for bastion (to download terraform files)
resource "aws_iam_role_policy" "bastion_s3" {
  count = local.create_bastion ? 1 : 0
  name  = "${local.standard_prefix}-bastion-s3-policy"
  role  = aws_iam_role.bastion[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          local.deploy_stage1 ? aws_s3_bucket.creating_bucket_sensitive_data[0].arn : "arn:aws:s3:::*",
          local.deploy_stage1 ? "${aws_s3_bucket.creating_bucket_sensitive_data[0].arn}/*" : "arn:aws:s3:::*/*"
        ]
      }
    ]
  })
}

# Instance profile
resource "aws_iam_instance_profile" "bastion" {
  count = local.create_bastion ? 1 : 0
  name  = "${local.standard_prefix}-bastion-profile"
  role  = aws_iam_role.bastion[0].name

  tags = local.tags
}

# VPC Endpoints for SSM (so bastion doesn't need internet access)
resource "aws_vpc_endpoint" "ssm" {
  count               = local.create_bastion ? 1 : 0
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "${local.standard_prefix}-ssm-endpoint"
    }
  )
}

resource "aws_vpc_endpoint" "ssmmessages" {
  count               = local.create_bastion ? 1 : 0
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "${local.standard_prefix}-ssmmessages-endpoint"
    }
  )
}

resource "aws_vpc_endpoint" "ec2messages" {
  count               = local.create_bastion ? 1 : 0
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "${local.standard_prefix}-ec2messages-endpoint"
    }
  )
}

# VPC Endpoint for S3 (Gateway endpoint - free!)
resource "aws_vpc_endpoint" "s3" {
  count             = local.create_bastion ? 1 : 0
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.deploy_stage1 ? [module.vpc[0].private_route_table_ids[0]] : []

  tags = merge(
    local.tags,
    {
      Name = "${local.standard_prefix}-s3-endpoint"
    }
  )
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  count       = local.create_bastion ? 1 : 0
  name        = "${local.standard_prefix}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  tags = merge(
    local.tags,
    {
      Name = "${local.standard_prefix}-vpc-endpoints-sg"
    }
  )
}

# Bastion EC2 instance (now in PRIVATE subnet, no public IP needed!)
resource "aws_instance" "bastion" {
  count                       = local.create_bastion ? 1 : 0
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t3.micro"
  subnet_id                   = local.private_subnets[0] # Changed to private subnet
  vpc_security_group_ids      = [aws_security_group.bastion[0].id]
  iam_instance_profile        = aws_iam_instance_profile.bastion[0].name
  associate_public_ip_address = false # No public IP needed with VPC endpoints!

  user_data = <<-EOF
#!/bin/bash
set -x
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting user-data script..."

# Install kubectl with retry loop
for i in {1..5}; do
  K8S_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
  if [ ! -z "$K8S_VERSION" ]; then break; fi
  sleep 5
done
K8S_VERSION=$${K8S_VERSION:-v1.29.0}
curl -LO "https://dl.k8s.io/release/$K8S_VERSION/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install terraform
yum install -y yum-utils
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
yum -y install terraform

# Install git
yum install -y git

# Install python3 and pip (for attack simulation)
yum install -y python3 python3-pip

# Install nano (user-friendly text editor)
yum install -y nano

# Create a script to download terraform files from S3
cat > /home/ec2-user/download_terraform.sh << 'DOWNLOAD'
#!/bin/bash
set -e

echo "=== Downloading Terraform Files from S3 ==="
echo ""

# Find the S3 bucket
echo "Looking for S3 bucket..."
BUCKET_NAME=$(aws s3 ls | grep selenium-prod | awk '{print $3}')

if [ -z "$BUCKET_NAME" ]; then
  echo "ERROR: Could not find S3 bucket!"
  echo "Make sure Stage 1 was deployed successfully."
  exit 1
fi

echo "Found bucket: $BUCKET_NAME"
echo ""

# Download terraform files
echo "Downloading terraform-files.tar.gz..."
aws s3 cp s3://$BUCKET_NAME/stage2/terraform-files.tar.gz .

if [ ! -f terraform-files.tar.gz ]; then
  echo "ERROR: Download failed!"
  echo ""
  echo "Make sure you uploaded the files from your laptop:"
  echo "  tar -czf terraform-files.tar.gz *.tf scripts/ data/ terraform.tfvars"
  echo "  aws s3 cp terraform-files.tar.gz s3://$BUCKET_NAME/stage2/"
  exit 1
fi

# Extract
echo "Extracting files..."
tar -xzf terraform-files.tar.gz

# Verify
echo ""
echo "Files extracted successfully:"
ls -lh *.tf

echo ""
echo "=== Next Steps ==="
echo "1. Set Wiz credentials:"
echo "   export WIZ_CLIENT_ID=\"your-client-id\""
echo "   export WIZ_CLIENT_SECRET=\"your-client-secret\""
echo ""
echo "2. Update terraform.tfvars:"
echo "   deployment_stage = \"stage2\""
echo "   create_bastion_host = false"
echo ""
echo "3. Deploy Stage 2:"
echo "   terraform init"
echo "   terraform apply"
echo ""
echo "4. After EKS is created, configure kubectl:"
echo "   ./setup-kubectl.sh"
DOWNLOAD

chmod +x /home/ec2-user/download_terraform.sh
chown ec2-user:ec2-user /home/ec2-user/download_terraform.sh

# Create a setup script for stage2 deployment (kubectl configuration)
cat > /home/ec2-user/setup-kubectl.sh << SETUP
#!/bin/bash
echo "=== Configuring kubectl for EKS Cluster ==="
echo ""

# Configure kubectl for the EKS cluster (run this after EKS is created)
CLUSTER_NAME="${local.cluster_name}"
REGION="${var.aws_region}"

echo "Cluster: \$CLUSTER_NAME"
echo "Region: \$REGION"
echo ""

echo "Updating kubeconfig..."
aws eks update-kubeconfig --name \$CLUSTER_NAME --region \$REGION

echo ""
echo "Testing kubectl access..."
kubectl get nodes

echo ""
echo "=== Setup Complete! ==="
echo "You can now use kubectl to manage the cluster."
SETUP

chmod +x /home/ec2-user/setup-kubectl.sh
chown ec2-user:ec2-user /home/ec2-user/setup-kubectl.sh

# Create a README for the user
cat > /home/ec2-user/README.txt << 'README'
Welcome to the AWS Attack Simulation Bastion Host!

This host is in a PRIVATE SUBNET with no direct internet access.
All AWS service communication is via VPC Endpoints.

NEXT STEPS:

1. Download Terraform files from S3:

   # Find the S3 bucket (created in Stage 1)
   BUCKET_NAME=$(aws s3 ls | grep selenium-prod | awk '{print $3}')
   echo "Bucket: $BUCKET_NAME"

   # Download the terraform files
   aws s3 cp s3://$BUCKET_NAME/stage2/terraform-files.tar.gz .

   # Extract
   tar -xzf terraform-files.tar.gz

   # Verify
   ls -la *.tf

2. Set your Wiz credentials:
   export WIZ_CLIENT_ID="your-client-id"
   export WIZ_CLIENT_SECRET="your-client-secret"

3. Update terraform.tfvars:
   deployment_stage = "stage2"
   create_bastion_host = false

4. Deploy stage 2:
   terraform init
   terraform apply

5. After EKS is created, configure kubectl:
   ./setup-kubectl.sh

INSTALLED TOOLS:
- Terraform
- kubectl
- Helm
- git
- AWS CLI
- Python 3

NETWORK ACCESS:
- VPC Endpoints: SSM, S3 (private)
- NAT Gateway: HTTPS/HTTP to internet (for package downloads)
- No public IP address

For detailed instructions, see: TWO_STAGE_DEPLOYMENT.md
README

chown ec2-user:ec2-user /home/ec2-user/README.txt

echo "User-data script completed successfully!"
EOF

  tags = merge(
    local.tags,
    {
      Name = "${local.standard_prefix}-bastion"
    }
  )

  depends_on = [
    module.vpc,
    aws_vpc_endpoint.ssm,
    aws_vpc_endpoint.ssmmessages,
    aws_vpc_endpoint.ec2messages,
    aws_vpc_endpoint.s3
  ]
}

