# Before applying, set these values for your environment.
# gitops_repo_url: HTTPS URL of your fork of this repository (ArgoCD reads from it).
# github_actions_repo: org/repo of the GitHub repository running the workflow (used for OIDC trust policy).
# tf_state_bucket: name of your S3 bucket for Terraform remote state.
cluster_name          = "my-eks-cluster"
environment           = "dev"
aws_region            = "us-east-1"
kubernetes_version    = "1.36"
gitops_repo_url       = "https://github.com/<your-org>/sample-eks-upgrade-gitops-argocd.git"
github_actions_repo   = "<your-org>/sample-eks-upgrade-gitops-argocd"
tf_state_bucket       = "<your-tf-state-bucket>"
