module "eks" {
  # checkov:skip=CKV_TF_1: Terraform Registry modules publish immutable versioned
  # artifacts. Exact version pinning provides equivalent supply-chain protection to a
  # git commit hash; the ?ref=<SHA> pattern applies only to git:: source URLs.
  source  = "terraform-aws-modules/eks/aws"
  version = "20.36.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  enable_irsa = true

  # Allow the Terraform caller identity to administer the cluster without
  # needing a separate aws-auth ConfigMap entry.
  enable_cluster_creator_admin_permissions = true

  vpc_id     = var.vpc_id != "" ? var.vpc_id : module.vpc.vpc_id
  subnet_ids = length(var.private_subnet_ids) > 0 ? var.private_subnet_ids : module.vpc.private_subnets

  cluster_addons = {
    coredns = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "PRESERVE"
    }

    kube-proxy = {
      most_recent                 = true
      resolve_conflicts_on_update = "PRESERVE"
    }

    vpc-cni = {
      most_recent                 = true
      resolve_conflicts_on_update = "PRESERVE"
      service_account_role_arn    = module.vpc_cni_irsa.iam_role_arn
    }

    aws-ebs-csi-driver = {
      most_recent                 = true
      resolve_conflicts_on_update = "PRESERVE"
      service_account_role_arn    = module.ebs_csi_irsa.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    primary = {
      instance_types = var.node_group_instance_types
      ami_type       = "AL2_x86_64"

      min_size     = var.node_group_min_size
      max_size     = var.node_group_max_size
      desired_size = var.node_group_desired_size

      # Limit node group rolling update disruption to 33% of nodes at a time.
      update_config = {
        max_unavailable_percentage = 33
      }

      labels = {
        role        = "general"
        environment = var.environment
      }

      tags = local.common_tags
    }
  }

  tags = local.common_tags
}

# IRSA role for VPC CNI to manage ENIs without node-level IAM permissions.
module "vpc_cni_irsa" {
  # checkov:skip=CKV_TF_1: Terraform Registry module pinned to an exact immutable version.
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.44.0"

  role_name             = "${var.cluster_name}-vpc-cni-irsa"
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }

  tags = local.common_tags
}

# IRSA role for EBS CSI Driver to provision and attach EBS volumes.
module "ebs_csi_irsa" {
  # checkov:skip=CKV_TF_1: Terraform Registry module pinned to an exact immutable version.
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.44.0"

  role_name             = "${var.cluster_name}-ebs-csi-irsa"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.common_tags
}
