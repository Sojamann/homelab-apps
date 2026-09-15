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
  CFG["infrastructure/configs/dashboards<br/>K8s Overview - K8s Detail"] -->|configMapGenerator| DASH

  GW["Gateway lab"] -->|grafana.app_domain| GR
```

> **Storage Note** data is dropped after 30 days or when it reaches 18GB.

## Dashboards

The chart's own are off. Ours live in `infrastructure/configs/dashboards/`, in
the Grafana folder **K8s**:

| Dashboard    | For                                                                 |
|--------------|---------------------------------------------------------------------|
| K8s Overview | the quick look -- CPU, memory (usage + requests), network, disk per node; what each PVC holds |
| K8s Detail   | digging in -- stats, per namespace, per pod CPU/throttling/memory, a pods table |

Anything else is in Prometheus and reachable through Explore.

**Changing one:** edit in the UI, Share -> Export -> paste over the JSON file,
commit. Grafana is stateless, so an unexported edit is gone on the next restart.
A new dashboard is a new file plus a `configMapGenerator` entry.
