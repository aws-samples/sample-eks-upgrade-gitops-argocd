# Before applying, set gitops_repo_url to your own fork of this repository.
# ArgoCD reads cluster-config.yaml and the ApplicationSets from this URL.
cluster_name       = "my-eks-cluster"
environment        = "dev"
aws_region         = "us-east-1"
kubernetes_version = "1.32"
gitops_repo_url    = "https://github.com/<your-org>/eks-upgrade-gitops-argocd.git"
