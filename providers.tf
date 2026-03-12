provider "aws" {
  region = var.aws_region
}

provider "wiz" {
  environment = "prod"
}

provider "kubernetes" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = local.cluster_ca != "" ? base64decode(local.cluster_ca) : ""
  token                  = local.deploy_stage2 ? data.aws_eks_cluster_auth.eks[0].token : ""
}

provider "helm" {
  kubernetes {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = local.cluster_ca != "" ? base64decode(local.cluster_ca) : ""
    token                  = local.deploy_stage2 ? data.aws_eks_cluster_auth.eks[0].token : ""
  }
}
