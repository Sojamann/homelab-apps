# Monitoring

kube-prometheus-stack: Prometheus, Alertmanager and Grafana, plus the exporters
for the cluster itself.

Grafana is `grafana.${app_domain}`: anonymous visitors are Viewers, the admin
is in OpenBao (`bao kv get kv/monitoring/grafana`). Prometheus and Alertmanager
have no auth and no route:

```mermaid
graph TD
  subgraph mon["ns: monitoring (privileged)"]
    OP["prometheus-operator"]
    PROM["Prometheus<br/>30d / 18GB - sc fast 20Gi"]
    AM["Alertmanager<br/>no receiver - sc fast 1Gi"]
    GR["Grafana<br/>stateless - anonymous Viewer"]
    NE["node-exporter<br/>DaemonSet"]
    KSM["kube-state-metrics"]
    SEC[["ExternalSecret grafana-admin<br/>kv/monitoring/grafana"]]
    OP -->|manages| PROM & AM
    SEC --> GR
    GR -->|queries| PROM
    PROM -->|alerts| AM
  end

  PROM -->|scrapes| NE & KSM
  PROM -->|scrapes| K["apiserver - kubelet/cAdvisor - CoreDNS"]
  PROM -.->|any namespace| MON["ServiceMonitor - PodMonitor<br/>ScrapeConfig - PrometheusRule"]
  GR -.->|any namespace| DASH["ConfigMap<br/>grafana_dashboard: 1"]
  CFG["infrastructure/configs/dashboards<br/>k8s/ - nas/"] -->|configMapGenerator| DASH
  NAS["infrastructure/configs/nas<br/>ScrapeConfig - PrometheusRule"] --> MON
  PVE["infrastructure/configs/proxmox<br/>ScrapeConfig - PrometheusRule"] --> MON
  PROM -->|scrapes :9100| TN["TrueNAS node-exporter<br/>10.212.4.150 - see machines/truenas.md"]
  PROM -->|scrapes :9100 - :9221<br/>via metrics-allow-proxmox| PX["Proxmox hosts<br/>node-exporter + pve-exporter"]

  GW["Gateway lab"] -->|grafana.app_domain| GR
```

> **Storage Note** data is dropped after 30 days or when it reaches 18GB.

## Dashboards

The chart's own are off. Ours live in `infrastructure/configs/dashboards/`, one
directory per Grafana folder:

| Folder | Dashboard    | For                                                                 |
|--------|--------------|---------------------------------------------------------------------|
| K8s    | K8s Overview | the quick look -- CPU, memory (usage + requests), network, disk per node; what each PVC holds |
| K8s    | K8s Detail   | digging in -- stats, per namespace, per pod CPU/throttling/memory, a pods table |
| NAS    | NAS          | pool fill + state, CPU, memory with ARC split out, ARC hit ratio, network |

Anything else is in Prometheus and reachable through Explore.

**Changing one:** edit in the UI, Share -> Export -> paste over the JSON file,
commit. Grafana is stateless, so an unexported edit is gone on the next restart.
A new dashboard is a new file plus a `configMapGenerator` entry; a new folder
is a new directory.
