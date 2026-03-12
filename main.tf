locals {
  prefix      = "selenium"
  environment = "prod"
  # Use provided deployment_id or fall back to random_id (for backwards compatibility)
  deployment_id = var.deployment_id != "" ? var.deployment_id : random_id.unique_id.hex
  tags          = merge(var.tags, { wiz-simulation : "true" })

  standard_prefix = "${local.prefix}-${local.environment}-${local.deployment_id}"
  vpc_cidr        = var.vpc_cidr
  azs             = slice(data.aws_availability_zones.available.names, 0, var.vpc_subnets)

  # Deployment stage control
  deploy_stage1 = var.deployment_stage == "stage1" || var.deployment_stage == "all"
  deploy_stage2 = var.deployment_stage == "stage2" || var.deployment_stage == "all"

  # AWS Infrastructure (VPC, EKS Module, IAM) -> Stage 1
  manage_aws_infra = local.deploy_stage1

  # Kubernetes App Resources (Namespace, Helm, Selenium) -> Stage 2
  manage_k8s_resources = local.deploy_stage2

  cluster_suffix = local.deploy_stage1 ? "-${random_id.cluster_random[0].hex}" : ""
  cluster_name   = "${local.standard_prefix}${local.cluster_suffix}"

  cluster_admins = length(var.cluster_admins) > 0 ? var.cluster_admins : [data.aws_iam_session_context.current.issuer_arn]

  # Reconstruct the bastion role ARN to avoid dependency issues while ensuring it's in the admin list
  bastion_role_arn = "arn:${data.aws_partition.current.id}:iam::${data.aws_caller_identity.current.account_id}:role/${local.standard_prefix}-bastion-role"

  cluster_admin_access_entries = merge(
    {
      for i, user in local.cluster_admins :
      "cluster_admin_${i + 1}" => {
        principal_arn = "${user}"
        type          = "STANDARD"

        policy_associations = {
          admin = {
            policy_arn = "arn:${data.aws_partition.current.id}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = {
              type = "cluster"
            }
          }
        }
      }
    },
    var.create_bastion_host ? {
      bastion_admin = {
        principal_arn = local.bastion_role_arn
        type          = "STANDARD"
        policy_associations = {
          admin = {
            policy_arn = "arn:${data.aws_partition.current.id}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = {
              type = "cluster"
            }
          }
        }
      }
    } : {}
  )

  # VPC references - use module outputs in stage1/all, use data sources in stage2
  vpc_id          = local.deploy_stage1 ? module.vpc[0].vpc_id : data.aws_vpc.existing[0].id
  intra_subnets   = local.deploy_stage1 ? module.vpc[0].intra_subnets : data.aws_subnets.intra[0].ids
  private_subnets = local.deploy_stage1 ? module.vpc[0].private_subnets : data.aws_subnets.private[0].ids

  # EKS Connection info for providers
  # In stage2, we discovery the cluster name dynamically to support the random suffix
  discovered_cluster_name = local.manage_k8s_resources ? (local.deploy_stage1 ? module.simu_kubernetes_cluster[0].cluster_name : try([for n in data.aws_eks_clusters.all[0].names : n if can(regex("^${local.standard_prefix}-", n))][0], "")) : ""

  cluster_endpoint         = local.manage_k8s_resources ? (local.deploy_stage1 ? module.simu_kubernetes_cluster[0].cluster_endpoint : try(data.aws_eks_cluster.existing_cluster[0].endpoint, "")) : ""
  cluster_ca               = local.manage_k8s_resources ? (local.deploy_stage1 ? module.simu_kubernetes_cluster[0].cluster_certificate_authority_data : try(data.aws_eks_cluster.existing_cluster[0].certificate_authority[0].data, "")) : ""
  cluster_id               = local.manage_k8s_resources ? (local.deploy_stage1 ? module.simu_kubernetes_cluster[0].cluster_id : try(data.aws_eks_cluster.existing_cluster[0].id, "")) : ""
  cluster_name_actual      = local.manage_k8s_resources ? (local.deploy_stage1 ? module.simu_kubernetes_cluster[0].cluster_name : try(data.aws_eks_cluster.existing_cluster[0].name, "")) : ""
  cluster_status           = local.manage_k8s_resources ? (local.deploy_stage1 ? module.simu_kubernetes_cluster[0].cluster_status : try(data.aws_eks_cluster.existing_cluster[0].status, "")) : ""
  cluster_platform_version = local.manage_k8s_resources ? (local.deploy_stage1 ? module.simu_kubernetes_cluster[0].cluster_platform_version : try(data.aws_eks_cluster.existing_cluster[0].platform_version, "")) : ""
  cluster_oidc_issuer_url  = local.manage_k8s_resources ? (local.deploy_stage1 ? module.simu_kubernetes_cluster[0].cluster_oidc_issuer_url : try(data.aws_eks_cluster.existing_cluster[0].identity[0].oidc[0].issuer, "")) : ""

  # For OIDC provider ARN, we reconstruct it if in stage 2 since it's not in the cluster data source
  cluster_oidc_provider_arn = local.manage_k8s_resources ? (local.deploy_stage1 ? module.simu_kubernetes_cluster[0].oidc_provider_arn : try("arn:${data.aws_partition.current.id}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.existing_cluster[0].identity[0].oidc[0].issuer, "https://", "")}", "")) : ""
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

data "aws_partition" "current" {}

# Data sources for stage2 deployment (when VPC already exists)
data "aws_vpc" "existing" {
  count = local.deploy_stage2 && !local.deploy_stage1 ? 1 : 0

  filter {
    name   = "tag:Name"
    values = ["${local.standard_prefix}-vpc"]
  }
}

data "aws_subnets" "private" {
  count = local.deploy_stage2 && !local.deploy_stage1 ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing[0].id]
  }

  filter {
    name   = "tag:kubernetes.io/role/internal-elb"
    values = ["1"]
  }
}

data "aws_subnets" "intra" {
  count = local.deploy_stage2 && !local.deploy_stage1 ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing[0].id]
  }

  filter {
    name   = "tag:Name"
    values = ["*intra*"]
  }
}

data "aws_eks_clusters" "all" {
  count = local.manage_k8s_resources && !local.deploy_stage1 ? 1 : 0
}

data "aws_eks_cluster" "existing_cluster" {
  count = local.manage_k8s_resources && !local.deploy_stage1 ? 1 : 0
  name  = local.discovered_cluster_name
}

data "aws_eks_cluster_auth" "eks" {
  count = local.manage_k8s_resources ? 1 : 0
  name  = local.manage_aws_infra ? local.cluster_name : local.discovered_cluster_name
}

data "kubernetes_service" "selenium" {
  count = local.deploy_stage2 ? 1 : 0
  metadata {
    name      = "selenium-grid-service"
    namespace = "default"
  }
  depends_on = [
    kubernetes_service.selenium_service,
  ]
}

module "vpc" {
  count   = local.deploy_stage1 ? 1 : 0
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.standard_prefix}-vpc"
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  enable_flow_log           = var.enable_flow_log
  flow_log_destination_type = var.flow_log_destination_type
  flow_log_destination_arn  = var.flow_log_destination_arn

  # Ensure all subnets have required tags
  public_subnet_tags = merge(
    {
      "kubernetes.io/role/elb" = 1
    },
    local.tags
  )

  private_subnet_tags = merge(
    {
      "kubernetes.io/role/internal-elb" = 1
    },
    local.tags
  )

  # Apply tags to all VPC resources
  tags = local.tags

  # Additional tags for specific VPC components
  vpc_tags                    = local.tags
  igw_tags                    = local.tags
  nat_eip_tags                = local.tags
  nat_gateway_tags            = local.tags
  default_network_acl_tags    = local.tags
  default_route_table_tags    = local.tags
  default_security_group_tags = local.tags
}

module "simu_kubernetes_cluster" {
  count   = local.manage_aws_infra ? 1 : 0
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name                    = local.cluster_name
  cluster_version                 = var.cluster_version
  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  cluster_endpoint_private_access = var.cluster_endpoint_private_access

  access_entries = merge(local.cluster_admin_access_entries, var.access_entries)

  vpc_id                   = local.vpc_id
  subnet_ids               = local.private_subnets
  control_plane_subnet_ids = local.intra_subnets

  kms_key_administrators = local.cluster_admins

  eks_managed_node_group_defaults = {
    ami_type = "AL2023_x86_64_STANDARD"

  }

  eks_managed_node_groups = {
    general = {
      name            = "${local.standard_prefix}-nodes"
      create_iam_role = false
      iam_role_arn    = local.deploy_stage1 ? aws_iam_role.wiz-attack-simulation[0].arn : data.aws_iam_role.existing[0].arn
      instance_types  = ["t3.medium"]

      metadata_options = {
        http_endpoint = "enabled"
        http_tokens   = "optional"
      }

      min_size     = 1
      max_size     = 3
      desired_size = 1
    }
  }

  tags = local.tags

  create_cloudwatch_log_group = false

  # Allow bastion to communicate with the cluster API (required for private clusters)
  cluster_security_group_additional_rules = {
    ingress_bastion = {
      description              = "Allow HTTPS from bastion"
      protocol                 = "tcp"
      from_port                = 443
      to_port                  = 443
      type                     = "ingress"
      source_security_group_id = local.deploy_stage1 ? aws_security_group.bastion[0].id : data.aws_security_group.bastion[0].id
    }
  }
}

resource "time_sleep" "eks_wait" {
  count           = local.manage_aws_infra ? 1 : 0
  create_duration = var.cluster_create_wait

  depends_on = [module.simu_kubernetes_cluster]
}

resource "random_id" "cluster_random" {
  count       = local.deploy_stage1 ? 1 : 0
  byte_length = 2
}

resource "random_id" "unique_id" {
  byte_length = 4
}

##################################################################################################
# S3 Configuration (Stage 1)
##################################################################################################
resource "aws_s3_bucket" "creating_bucket_sensitive_data" {
  count  = local.deploy_stage1 ? 1 : 0
  bucket = "${local.standard_prefix}-bucket"

  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "creating_bucket_sensitive_data" {
  count  = local.deploy_stage1 ? 1 : 0
  bucket = aws_s3_bucket.creating_bucket_sensitive_data[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "creating_bucket_sensitive_data" {
  count  = local.deploy_stage1 ? 1 : 0
  bucket = aws_s3_bucket.creating_bucket_sensitive_data[0].id

  key    = "client_keys.txt"
  source = "${path.root}/data/s3/client_keys.txt"
  tags   = local.tags
}

##################################################################################################
# IAM Configuration (Stage 1)
##################################################################################################
resource "aws_iam_role" "wiz-attack-simulation" {
  count = local.deploy_stage1 ? 1 : 0
  name  = "wiz-attack-simulation-${local.deployment_id}"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "EKSNodeAssumeRole",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ec2.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "wiz-attack-simulation_policy_attachment" {
  for_each = local.deploy_stage1 ? toset([
    "arn:aws:iam::aws:policy/IAMFullAccess",
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  ]) : toset([])
  role       = aws_iam_role.wiz-attack-simulation[0].name
  policy_arn = each.key
}

# New policy for SSM parameter store access (PutParameter only)
resource "aws_iam_policy" "attack_sim_ssm" {
  count = local.deploy_stage1 ? 1 : 0
  name  = "wiz-attack-simulation-ssm-${local.deployment_id}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter" # Only PUT, no DELETE
        ]
        Resource = "arn:aws:ssm:*:*:parameter/attack-simulation/stolen-credentials"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attack_sim_ssm" {
  count      = local.deploy_stage1 ? 1 : 0
  role       = aws_iam_role.wiz-attack-simulation[0].name
  policy_arn = aws_iam_policy.attack_sim_ssm[0].arn
}

##################################################################################################
# SSM Parameter Store Configuration (Stage 2)
##################################################################################################
resource "aws_ssm_parameter" "selenium_grid_ip" {
  count     = local.manage_k8s_resources ? 1 : 0
  name      = "/attack-sims/aws/selenium-grid-ip"
  type      = "String"
  value     = data.kubernetes_service.selenium[0].status[0].load_balancer[0].ingress[0].hostname
  overwrite = true
}

resource "aws_ssm_parameter" "sensitive_bucket_name" {
  count     = local.manage_k8s_resources ? 1 : 0
  name      = "/attack-sims/aws/sensitive-bucket-name"
  type      = "String"
  value     = local.deploy_stage1 ? aws_s3_bucket.creating_bucket_sensitive_data[0].bucket : data.aws_s3_bucket.existing[0].bucket
  overwrite = true
}

resource "aws_ssm_parameter" "sensitive_bucket_key" {
  count     = local.manage_k8s_resources ? 1 : 0
  name      = "/attack-sims/aws/sensitive-bucket-key"
  type      = "String"
  value     = local.deploy_stage1 ? aws_s3_object.creating_bucket_sensitive_data[0].key : "client_keys.txt"
  overwrite = true
}

resource "aws_ssm_parameter" "selenium_grid_region" {
  count     = local.manage_k8s_resources ? 1 : 0
  name      = "/attack-sims/aws/selenium-grid-region"
  type      = "String"
  value     = var.aws_region
  overwrite = true
}

##################################################################################################
# Security Group for LoadBalancer (Stage 1)
##################################################################################################
resource "aws_security_group" "selenium_lb" {
  count       = local.deploy_stage1 ? 1 : 0
  name        = "${local.standard_prefix}-selenium-lb-sg"
  description = "Security group for Selenium Grid LoadBalancer with IP restrictions"
  vpc_id      = local.vpc_id

  ingress {
    description = "Selenium Grid port"
    from_port   = 24444
    to_port     = 24444
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    description = "Selenium Node VNC port"
    from_port   = 25900
    to_port     = 25900
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    description = "Allow Selenium Grid access from within VPC"
    from_port   = 24444
    to_port     = 24444
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.tags,
    {
      Name = "${local.standard_prefix}-selenium-lb-sg"
    }
  )
}

##################################################################################################
# Kubernetes Resources Configuration (Stage 2)
##################################################################################################

# Data source to find existing security group in stage2
data "aws_security_group" "selenium_lb" {
  count = local.deploy_stage2 && !local.deploy_stage1 ? 1 : 0

  filter {
    name   = "tag:Name"
    values = ["${local.standard_prefix}-selenium-lb-sg"]
  }

  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

# Data source to find existing S3 bucket in stage2
data "aws_s3_bucket" "existing" {
  count  = local.deploy_stage2 && !local.deploy_stage1 ? 1 : 0
  bucket = "${local.standard_prefix}-bucket"
}

# Data source to find existing IAM role in stage2
data "aws_iam_role" "existing" {
  count = local.deploy_stage2 && !local.deploy_stage1 ? 1 : 0
  name  = "wiz-attack-simulation-${local.deployment_id}"
}

# Data source to find existing bastion security group in stage2
data "aws_security_group" "bastion" {
  count = local.deploy_stage2 && !local.deploy_stage1 ? 1 : 0

  filter {
    name   = "tag:Name"
    values = ["${local.standard_prefix}-bastion-sg"]
  }

  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

resource "kubernetes_config_map" "cred_proxy_script" {
  count = local.manage_k8s_resources ? 1 : 0
  metadata {
    name      = "cred-proxy-script"
    namespace = "default"
  }

  data = {
    "cred_proxy.py" = file("${path.module}/scripts/cred_proxy.py")
  }
}

resource "kubernetes_service" "selenium_service" {
  count = local.manage_k8s_resources ? 1 : 0
  metadata {
    name      = "selenium-grid-service"
    namespace = "default"
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-security-groups" = local.deploy_stage1 ? aws_security_group.selenium_lb[0].id : data.aws_security_group.selenium_lb[0].id
      "service.beta.kubernetes.io/aws-load-balancer-type"            = "nlb"
    }
  }

  spec {
    type = "LoadBalancer"

    selector = {
      app = "selenium-grid"
    }

    port {
      name        = "grid-port"
      protocol    = "TCP"
      port        = 24444
      target_port = 24444
    }

    port {
      name        = "node-port"
      protocol    = "TCP"
      port        = 25900
      target_port = 25900
    }
  }

  depends_on = [
    kubernetes_deployment.selenium_deployment
  ]
}

resource "kubernetes_deployment" "selenium_deployment" {
  count = local.manage_k8s_resources ? 1 : 0
  metadata {
    name = "selenium-grid-app"
    labels = {
      app = "selenium-grid"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "selenium-grid"
      }
    }

    template {
      metadata {
        labels = {
          app = "selenium-grid"
        }
      }

      spec {
        host_network = true

        # Existing Selenium container
        container {
          name              = "selenium-grid"
          image             = "elgalu/selenium"
          image_pull_policy = "Always"

          port {
            container_port = 24444
          }

          port {
            container_port = 25900
          }
        }

        # Credential proxy sidecar container
        container {
          name  = "cred-proxy"
          image = "python:3.9-slim"

          command = ["sh", "-c", "pip install boto3 && python /scripts/cred_proxy.py"]

          volume_mount {
            name       = "cred-proxy-script"
            mount_path = "/scripts"
          }

          env {
            name  = "AWS_REGION"
            value = var.aws_region
          }
        }

        # Volume for the ConfigMap
        volume {
          name = "cred-proxy-script"

          config_map {
            name = kubernetes_config_map.cred_proxy_script[0].metadata[0].name

            items {
              key  = "cred_proxy.py"
              path = "cred_proxy.py"
              mode = "0755"
            }
          }
        }
      }
    }
  }

  depends_on = [module.simu_kubernetes_cluster]
}

resource "kubernetes_namespace" "wiz" {
  count = local.manage_k8s_resources ? 1 : 0
  metadata {
    name = "wiz"
  }
}

resource "wiz_service_account" "simu_kubernetes_sa" {
  count = local.manage_k8s_resources ? 1 : 0
  name  = "${local.standard_prefix}-sa"
  type  = "FIRST_PARTY"
}

resource "helm_release" "wiz_K8s_integration" {
  count            = local.manage_k8s_resources ? 1 : 0
  name             = "wiz-integration"
  namespace        = kubernetes_namespace.wiz[0].id
  create_namespace = false

  repository = "https://charts.wiz.io/"
  chart      = "wiz-kubernetes-integration"
  values = [
    <<-EOF
global:
  wizApiToken:
    clientId: ${wiz_service_account.simu_kubernetes_sa[0].client_id} # Client ID of the Wiz Service Account.
    clientToken: ${wiz_service_account.simu_kubernetes_sa[0].client_secret} # Client secret of the Wiz Service Account.
    clientEndpoint: ${var.wiz_k8s_integration_client_endpoint} # Wiz endpoint to connect to (required for gov tenants).

    secret:
      # Should a Secret be created by the chart or not.
      # Set this to false if you wish to create the Secret yourself or using another tool.
      # The Secret should contain clientId for the ID and clientToken for the token.
      create: true
      # Annotations to add to the secret.
      annotations: {}
      # The name of the Wiz Service Account Secret.
      name: "wiz-api-token"

  httpProxyConfiguration:
    enabled: false

#Local parameters section

wiz-kubernetes-connector:
  enabled: true

  broker:
    enabled: true

  autoCreateConnector:
    connectorName: ${local.standard_prefix}-connector
    clusterFlavor: EKS

wiz-admission-controller:
  enabled: ${var.use_wiz_admission_controller}

  kubernetesAuditLogsWebhook:
    enabled: ${var.use_wiz_admission_controller_audit_log}

wiz-sensor:
  enabled: ${var.use_wiz_sensor}
  imagePullSecret:
    # The default sensor registry requires a pull secret. Set to false
    # if mirroring the image.
    required: true
    # set to false when using an existing secret
    create: true

    # This value is a must in order to pull the image from a private repository. We use helm
    # to create a docker formatted json, encoded in base64.
    # In case you want use an existing value (perhaps created via "kubectl create secret docker-registry ...")
    # please mark "create" above as false
    username: ${var.wiz_sensor_pull_username}
    password: ${var.wiz_sensor_pull_password}
  EOF
  ]
  depends_on = [module.simu_kubernetes_cluster]
}

