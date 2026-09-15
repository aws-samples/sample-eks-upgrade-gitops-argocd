output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint URL for the EKS Kubernetes API server."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Current Kubernetes version running on the EKS cluster control plane."
  value       = module.eks.cluster_version
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the EKS cluster. Used by kubectl and other clients to verify the API server TLS certificate."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster. Used to create IRSA roles for add-ons."
  value       = module.eks.cluster_oidc_issuer_url
}

output "node_groups" {
  description = "Map of managed node group attributes keyed by node group name."
  value       = module.eks.eks_managed_node_groups
}

output "argocd_namespace" {
  description = "Kubernetes namespace where ArgoCD is installed."
  value       = var.argocd_namespace
}

output "github_actions_role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions via OIDC for EKS upgrade operations. Set this as the AWS_ROLE_ARN GitHub Actions secret."
  value       = aws_iam_role.github_actions_eks_upgrade.arn
}

output "vpc_cni_irsa_role_arn" {
  description = "ARN of the IRSA role attached to the VPC CNI service account."
  value       = module.vpc_cni_irsa.iam_role_arn
}

output "ebs_csi_irsa_role_arn" {
  description = "ARN of the IRSA role attached to the EBS CSI controller service account."
  value       = module.ebs_csi_irsa.iam_role_arn
}

output "configure_kubectl" {
  description = "AWS CLI command to update your local kubeconfig to connect to this cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
