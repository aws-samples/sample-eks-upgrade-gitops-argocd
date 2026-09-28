data "aws_caller_identity" "current" {}

# Register the GitHub Actions OIDC provider so GitHub can obtain short-lived
# AWS credentials without storing long-lived access keys as secrets.
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # Public TLS certificate thumbprints for token.actions.githubusercontent.com.
  # These are NOT secrets — they are the SHA-1 fingerprints of GitHub's OIDC
  # certificate chain and are safe to commit. AWS uses them to verify OIDC tokens.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1", # pragma: allowlist secret
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"  # pragma: allowlist secret
  ]

  tags = local.common_tags
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_actions_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions_eks_upgrade" {
  name               = "GitHubActionsEKSUpgradeRole"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
  description        = "Assumed by GitHub Actions via OIDC to perform EKS cluster version upgrades"

  tags = local.common_tags
}

data "aws_iam_policy_document" "github_actions_eks_upgrade_permissions" {
  # EKS permissions required for cluster version inspection and upgrade.
  statement {
    sid    = "EKSUpgradePermissions"
    effect = "Allow"
    actions = [
      "eks:DescribeCluster",
      "eks:UpdateClusterVersion",
      "eks:DescribeNodegroup",
      "eks:UpdateNodegroupVersion",
      "eks:UpdateNodegroupConfig",
      "eks:ListNodegroups",
      "eks:DescribeUpdate",
      "eks:ListUpdates",
      "eks:DescribeAddon",
      "eks:ListAddons",
      "eks:UpdateAddon",
      "eks:TagResource",
    ]
    resources = [
      "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}",
      "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:nodegroup/${var.cluster_name}/*/*",
      "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:addon/${var.cluster_name}/*/*",
    ]
  }

  # S3 permissions for Terraform remote state access.
  statement {
    sid    = "TerraformStateS3"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketVersioning",
    ]
    resources = [
      "arn:aws:s3:::${var.tf_state_bucket}",
      "arn:aws:s3:::${var.tf_state_bucket}/*",
    ]
  }

  # Minimal STS permission to confirm the assumed identity in validation scripts.
  statement {
    sid       = "GetCallerIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  # Read-only EC2 access. terraform plan refreshes the VPC, subnets, route
  # tables, NAT gateway, Elastic IP, security groups, and launch templates that
  # this configuration manages. EC2 Describe actions don't support
  # resource-level permissions, so the resource must be "*".
  statement {
    sid       = "EC2ReadForRefresh"
    effect    = "Allow"
    actions   = ["ec2:Describe*"]
    resources = ["*"]
  }

  # Read-only EKS access that isn't scoped to the cluster ARN: add-on version
  # lookups (most_recent = true) and the cluster creator's access entry.
  statement {
    sid    = "EKSReadForRefresh"
    effect = "Allow"
    actions = [
      "eks:DescribeAddonVersions",
      "eks:DescribeAccessEntry",
      "eks:ListAccessEntries",
      "eks:ListAssociatedAccessPolicies",
      "eks:ListTagsForResource",
    ]
    resources = ["*"]
  }

  # Read-only IAM access. terraform plan refreshes the cluster and node IAM
  # roles, the IRSA roles, the EKS and GitHub OIDC providers, and this role.
  statement {
    sid    = "IAMReadForRefresh"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:GetOpenIDConnectProvider",
    ]
    resources = ["*"]
  }

  # Read-only access to the KMS key and CloudWatch log group that the EKS
  # module creates for secrets encryption and control plane logs.
  statement {
    sid    = "KMSAndLogsReadForRefresh"
    effect = "Allow"
    actions = [
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListResourceTags",
      "kms:ListAliases",
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
      "logs:ListTagsLogGroup",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions_eks_upgrade" {
  name   = "EKSUpgradePolicy"
  role   = aws_iam_role.github_actions_eks_upgrade.id
  policy = data.aws_iam_policy_document.github_actions_eks_upgrade_permissions.json
}
