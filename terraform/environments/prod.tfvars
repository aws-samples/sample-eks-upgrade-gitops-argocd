# Before applying, set these values for your environment.
cluster_name        = "my-eks-cluster-prod"
environment         = "prod"
aws_region          = "us-east-1"
kubernetes_version  = "1.34"
gitops_repo_url     = "https://github.com/<your-org>/sample-eks-upgrade-gitops-argocd.git"
github_actions_repo = "<your-org>/sample-eks-upgrade-gitops-argocd"
tf_state_bucket     = "<your-tf-state-bucket>"
