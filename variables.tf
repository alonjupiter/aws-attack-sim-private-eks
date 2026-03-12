variable "cluster_admins" {
  type        = list(string)
  description = "A list containing the ARNs of users/roles that should be cluster administrators."
  default     = []
}

variable "aws_region" {
  type        = string
  description = "The AWS region in which to create resources."
}

variable "deployment_id" {
  type        = string
  description = "A unique identifier for this deployment. Used to name resources consistently across Stage 1 and Stage 2. If not provided, a random ID will be generated (not recommended for two-stage deployments)."
  default     = ""
}

variable "vpc_cidr" {
  type        = string
  description = "The CIDR subnet address for the created VPC."
  default     = "10.0.0.0/16"
}

variable "vpc_subnets" {
  type        = string
  description = "The number of subnets to configure for the created VPC."
  default     = 2
}

variable "wiz_k8s_integration_client_endpoint" {
  type        = string
  description = "A string representing the Client Endpoint for the Wiz Sensor service account."
  default     = "prod"
}

variable "wiz_sensor_pull_username" {
  type        = string
  description = "A string representing the image pull username for Wiz container images."
  default     = ""
}

variable "wiz_sensor_pull_password" {
  type        = string
  description = "A string representing the image pull password for Wiz container images."
  default     = ""
}

variable "use_wiz_admission_controller" {
  type        = bool
  description = "A boolean representing whether or not to deploy the Wiz Admission Controller in the EKS cluster."
  default     = false
}

variable "use_wiz_admission_controller_audit_log" {
  type        = bool
  description = "A boolean representing whether or not to use Wiz Admission Controller to gather EKS Logs."
  default     = false
}

variable "use_wiz_sensor" {
  type        = bool
  description = "A boolean representing whether or not to deploy the Wiz Sensor in the EKS cluster."
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "A map/dictionary of Tags to be assigned to created resources."
  default = {
    owner : "Wiz",
    project : "Attack Simulation",
  }
}

variable "access_entries" {
  type        = any
  description = "A map representing access entries to add to the EKS cluster."
  default     = {}
}

variable "cluster_create_wait" {
  type        = string
  description = "A string representing the time to wait after creating the EKS cluster before provisioning resources."
  default     = "60s"
}

variable "cluster_version" {
  type        = string
  description = "The kubernetes version for the EKS cluster."
  default     = "1.32"
}

variable "enable_flow_log" {
  type        = bool
  description = "A boolean representing whether to enable flow logs for the VPC."
  default     = false
}

variable "flow_log_destination_type" {
  type        = string
  description = "A string representing the destination type for the flow logs."
  default     = null

  validation {
    condition     = var.flow_log_destination_type == "s3" || var.flow_log_destination_type == null
    error_message = "The variable 'flow_log_destination_type' must be set to 's3'."
  }
}

variable "flow_log_destination_arn" {
  type        = string
  description = "The ARN of the destination for the flow logs."
  default     = null
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of CIDR blocks allowed to access the Selenium Grid LoadBalancer. Use your public IP/32 for maximum security. Default is open to internet (not recommended for production)."
  default     = ["0.0.0.0/0"]
}

variable "cluster_endpoint_public_access" {
  type        = bool
  description = "Whether the EKS cluster API endpoint should be publicly accessible. Set to false for maximum security (requires VPC access to manage cluster)."
  default     = false
}

variable "cluster_endpoint_private_access" {
  type        = bool
  description = "Whether the EKS cluster API endpoint should be privately accessible from within the VPC."
  default     = true
}

variable "create_bastion_host" {
  type        = bool
  description = "Whether to create a bastion host for managing the private EKS cluster. Only needed if cluster_endpoint_public_access = false."
  default     = true
}

variable "deployment_stage" {
  type        = string
  description = "Deployment stage: 'stage1' creates VPC and bastion only (run from local machine), 'stage2' creates EKS and kubernetes resources (run from bastion), 'all' creates everything (requires public EKS endpoint or VPC access)"
  default     = "all"

  validation {
    condition     = contains(["stage1", "stage2", "all"], var.deployment_stage)
    error_message = "deployment_stage must be 'stage1', 'stage2', or 'all'"
  }
}
