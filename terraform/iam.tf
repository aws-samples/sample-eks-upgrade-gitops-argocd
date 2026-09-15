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

    # Scope trust to pushes and pull requests from the specific GitOps repository.
    # Replace with your organization and repository name.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:aws-samples/sample-eks-upgrade-gitops-argocd:*"]
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
      "arn:aws:s3:::${var.cluster_name}-tf-state",
      "arn:aws:s3:::${var.cluster_name}-tf-state/*",
    ]
  }

  # DynamoDB permissions for Terraform state locking.
  statement {
    sid    = "TerraformStateLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/terraform-state-lock",
    ]
  }

  # Minimal STS permission to confirm the assumed identity in validation scripts.
  statement {
    sid       = "GetCallerIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  # EC2 permissions needed by Terraform EKS module to read VPC and subnet metadata.
  statement {
    sid    = "EC2ReadForEKSModule"
    effect = "Allow"
    actions = [
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeRouteTables",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeLaunchTemplateVersions",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions_eks_upgrade" {
  name   = "EKSUpgradePolicy"
  role   = aws_iam_role.github_actions_eks_upgrade.id
  policy = data.aws_iam_policy_document.github_actions_eks_upgrade_permissions.json
}
