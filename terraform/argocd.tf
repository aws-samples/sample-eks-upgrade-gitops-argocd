resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_version
  namespace        = var.argocd_namespace
  create_namespace = true

  # Wait for all ArgoCD pods to be ready before Terraform considers this resource complete.
  wait    = true
  timeout = 600

  values = [
    yamlencode({
      server = {
        service = {
          type = "LoadBalancer"
        }
        # NOTE: --insecure disables TLS on the ArgoCD server itself. This is acceptable when
        # TLS termination is handled by an external load balancer or ingress controller.
        # For production deployments, configure TLS certificates via cert-manager instead.
        extraArgs = ["--insecure"]
      }

      configs = {
        params = {
          "server.insecure" = true
        }
        cm = {
          # Allow applications in any namespace to be managed by ArgoCD ApplicationSets.
          "application.resourceTrackingMethod" = "annotation"
        }
      }

      # Resource limits for the ArgoCD application controller in production-scale clusters.
      applicationSet = {
        resources = {
          requests = {
            cpu    = "250m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "1Gi"
          }
        }
      }
    })
  ]

  depends_on = [module.eks]
}

# ArgoCD AppProject scoped to EKS upgrade management.
# This project allows ArgoCD to deploy resources to any cluster namespace,
# restricted to the GitOps repository defined in variables.
resource "kubectl_manifest" "argocd_appproject_eks_upgrades" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "eks-upgrades"
      namespace = var.argocd_namespace
      labels = {
        "managed-by" = "terraform"
      }
    }
    spec = {
      description = "Project for managing EKS cluster add-ons and upgrade state tracking"

      sourceRepos = [var.gitops_repo_url]

      destinations = [
        {
          server    = "https://kubernetes.default.svc"
          namespace = "*"
        }
      ]

      clusterResourceWhitelist = [
        {
          group = "*"
          kind  = "*"
        }
      ]

      namespaceResourceWhitelist = [
        {
          group = "*"
          kind  = "*"
        }
      ]

      # Orphan resource monitoring alerts when cluster resources exist that
      # are not tracked by any ArgoCD application in this project.
      orphanedResources = {
        warn = true
      }
    }
  })

  depends_on = [helm_release.argocd]
}
