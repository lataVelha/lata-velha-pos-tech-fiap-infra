resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  timeout    = 600
  wait       = true

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.region
  }

  set {
    name  = "rbac.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  # Credenciais injetadas via secret porque AWS Academy não permite IRSA
  values = [
    yamlencode({
      extraEnvs = [
        {
          name = "AWS_ACCESS_KEY_ID"
          valueFrom = {
            secretKeyRef = {
              name     = "aws-credentials"
              key      = "AWS_ACCESS_KEY_ID"
              optional = true
            }
          }
        },
        {
          name = "AWS_SECRET_ACCESS_KEY"
          valueFrom = {
            secretKeyRef = {
              name     = "aws-credentials"
              key      = "AWS_SECRET_ACCESS_KEY"
              optional = true
            }
          }
        },
        {
          name = "AWS_SESSION_TOKEN"
          valueFrom = {
            secretKeyRef = {
              name     = "aws-credentials"
              key      = "AWS_SESSION_TOKEN"
              optional = true
            }
          }
        }
      ]
    })
  ]
}
