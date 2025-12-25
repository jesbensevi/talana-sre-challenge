resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "5.51.6" 


  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }


  set {
    name  = "server.extraArgs"
    value = "{--insecure}"
  }


  timeout = 600
}