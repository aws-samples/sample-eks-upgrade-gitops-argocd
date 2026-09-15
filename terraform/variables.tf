variable "cluster_name" {
  description = "Name of the EKS cluster. Used as a prefix for all related resources."
  type        = string
}

variable "kubernetes_version" {
  description = "Target Kubernetes version for the EKS cluster. Changing this value and running terraform apply triggers the control plane upgrade. Must be a single-minor-version increment from the current cluster version."
  type        = string
  default     = "1.32"

  validation {
    condition     = can(regex("^1\\.(2[89]|3[0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must be a supported EKS version in the format 1.XX (for example, 1.29, 1.30, 1.31)."
  }
}

variable "environment" {
  description = "Deployment environment. Used for resource tagging and naming. Must be one of: dev, staging, prod."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS Region where the EKS cluster and supporting resources are deployed."
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "ID of an existing VPC. Leave empty to create a new VPC automatically."
  type        = string
  default     = ""
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS node groups. Leave empty to use subnets from the auto-created VPC."
  type        = list(string)
  default     = []
}

variable "node_group_instance_types" {
  description = "List of EC2 instance types for the EKS managed node group. The first type in the list is preferred; others are fallbacks."
  type        = list(string)
  default     = ["m5.xlarge"]
}

variable "node_group_min_size" {
  description = "Minimum number of nodes in the managed node group."
  type        = number
  default     = 2

  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "node_group_min_size must be at least 1."
  }
}

variable "node_group_max_size" {
  description = "Maximum number of nodes in the managed node group. Must be greater than or equal to node_group_desired_size."
  type        = number
  default     = 6
}

variable "node_group_desired_size" {
  description = "Desired number of nodes in the managed node group at steady state."
  type        = number
  default     = 3
}

variable "argocd_version" {
  description = "Helm chart version for ArgoCD (argo/argo-cd). Check https://github.com/argoproj/argo-helm/releases for the latest version."
  type        = string
  default     = "7.3.11"
}

variable "argocd_namespace" {
  description = "Kubernetes namespace where ArgoCD is installed."
  type        = string
  default     = "argocd"
}

variable "gitops_repo_url" {
  description = "HTTPS URL of the GitOps repository that contains cluster-config.yaml files and ArgoCD ApplicationSets."
  type        = string
}

variable "gitops_repo_branch" {
  description = "Branch of the GitOps repository that ArgoCD tracks for application definitions."
  type        = string
  default     = "main"
}
