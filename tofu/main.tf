terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "2.17.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.36.0"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# Create monitoring namespace
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

# PVC for Prometheus data using Longhorn
resource "kubernetes_persistent_volume_claim" "prometheus_data" {
  metadata {
    name      = "prometheus-data"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "5Gi"
      }
    }

    storage_class_name = "longhorn"
  }
}

# PVC for Grafana data using Longhorn
resource "kubernetes_persistent_volume_claim" "grafana_data" {
  metadata {
    name      = "grafana-data"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "1Gi"
      }
    }

    storage_class_name = "longhorn"
  }
}

# Helm chart for Prometheus Operator stack
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "70.7.0"

  values = [
    <<EOF
# Prometheus config
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi

# Grafana config
grafana:
  persistence:
    enabled: true
    existingClaim: grafana-data
  adminPassword: 428hfJKSDUb!nfiod?d0wf

  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: prometheus-longhorn
          type: prometheus
          url: http://kube-prometheus-kube-prome-prometheus.monitoring.svc:9090
          access: proxy
          isDefault: true
EOF
  ]
}

resource "kubernetes_manifest" "longhorn_service_monitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "longhorn"
      namespace = "monitoring"
    }
    spec = {
      selector = {
        matchLabels = {
          app = "longhorn-manager"
        }
      }
      namespaceSelector = {
        matchNames = ["longhorn-system"]
      }
      endpoints = [
        {
          port     = "manager"
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  }
}

