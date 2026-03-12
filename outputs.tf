output "selenium-grid-service-ip" {
  value = local.deploy_stage2 ? try(data.kubernetes_service.selenium[0].status[0].load_balancer[0].ingress[0].hostname, "Pending/Not available") : "Not deployed (stage2 only)"
}

output "kubernetes_connector_name" {
  value = "${local.standard_prefix}-connector"
}

output "bucket_arn" {
  value       = local.deploy_stage1 ? aws_s3_bucket.creating_bucket_sensitive_data[0].arn : (local.deploy_stage2 ? data.aws_s3_bucket.existing[0].arn : "Not deployed (stage1 only)")
  description = "The ARN of the S3 bucket created"
}

output "bucket_name" {
  value       = local.deploy_stage1 ? aws_s3_bucket.creating_bucket_sensitive_data[0].bucket : (local.deploy_stage2 ? data.aws_s3_bucket.existing[0].bucket : "Not deployed (stage1 only)")
  description = "The name of the S3 bucket created"
}

output "cluster_admin_access_entries" {
  value = local.cluster_admin_access_entries
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = local.cluster_ca != "" ? local.cluster_ca : "Not deployed (stage2 only)"
}

output "cluster_endpoint" {
  description = "Endpoint for the Kubernetes API server"
  value       = local.cluster_endpoint != "" ? local.cluster_endpoint : "Not deployed (stage2 only)"
}

output "cluster_id" {
  description = "The ID of the EKS cluster. Note: currently a value is returned only for local EKS clusters created on Outposts"
  value       = local.cluster_id != "" ? local.cluster_id : "Not deployed (stage2 only)"
}

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = local.cluster_name_actual != "" ? local.cluster_name_actual : "Not deployed (stage2 only)"
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = local.cluster_oidc_issuer_url != "" ? local.cluster_oidc_issuer_url : "Not deployed (stage2 only)"
}

output "cluster_platform_version" {
  description = "Platform version for the cluster"
  value       = local.cluster_platform_version != "" ? local.cluster_platform_version : "Not deployed (stage2 only)"
}

output "cluster_oidc_provider_arn" {
  description = "The ARN of the OIDC provider for the EKS cluster"
  value       = local.cluster_oidc_provider_arn != "" ? local.cluster_oidc_provider_arn : "Not deployed (stage2 only)"
}

output "cluster_status" {
  description = "Status of the EKS cluster. One of `CREATING`, `ACTIVE`, `DELETING`, `FAILED`"
  value       = local.cluster_status != "" ? local.cluster_status : "Not deployed (stage2 only)"
}

output "vpc_id" {
  description = "The ID of the VPC created for the simulation."
  value       = local.deploy_stage1 ? module.vpc[0].vpc_id : data.aws_vpc.existing[0].id
}

output "vpc_private_subnets" {
  description = "The IDs of the private subnets in the VPC created for the simulation."
  value       = local.deploy_stage1 ? module.vpc[0].private_subnets : data.aws_subnets.private[0].ids
}


