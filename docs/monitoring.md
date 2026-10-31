# Monitoring

kube-prometheus-stack: Prometheus, Alertmanager and Grafana, plus the exporters
for the cluster itself.

Rules, scrapes and dashboards for things no app owns live in
`infrastructure/configs/`; an app's own sit beside it. Prometheus has no
route.

```mermaid
graph TD
  subgraph mon["ns: monitoring (privileged)"]
    OP["prometheus-operator"]
    PROM["Prometheus<br/>30d / 18GB - sc fast 20Gi"]
    AM["Alertmanager<br/>sc fast 1Gi"]
    GR["Grafana<br/>stateless - anonymous Viewer"]
    NE["node-exporter<br/>DaemonSet"]
    KSM["kube-state-metrics"]
    SEC[["ExternalSecret grafana-admin<br/>kv/monitoring/grafana"]]
    SECA[["ExternalSecret alerting<br/>kv/monitoring/alerting"]]
    SECO[["ExternalSecret grafana-oidc<br/>kv/monitoring/grafana-oidc"]]
    OP -->|manages| PROM & AM
    SEC --> GR
    SECO -->|GF_AUTH_GENERIC_OAUTH_*| GR
    SECA -->|mounted as files| AM
    GR -->|queries| PROM
    PROM -->|alerts| AM
  end

  PROM -->|scrapes| NE & KSM
  PROM -->|scrapes| K["apiserver - kubelet/cAdvisor - CoreDNS"]
  PROM -.->|any namespace| MON["ServiceMonitor - PodMonitor<br/>ScrapeConfig - PrometheusRule"]
  GR -.->|any namespace| DASH["ConfigMap<br/>grafana_dashboard: 1"]
  CFG["infrastructure/configs/dashboards"] -->|configMapGenerator| DASH
  NAS["infrastructure/configs/nas<br/>ScrapeConfig - PrometheusRule"] --> MON
  PVE["infrastructure/configs/proxmox<br/>ScrapeConfig - PrometheusRule"] --> MON
  GA["infrastructure/configs/garage<br/>ScrapeConfig - PrometheusRule"] --> MON
  VS["infrastructure/configs/volsync<br/>PrometheusRule - see volsync.md"] --> MON
  PROM -->|scrapes :9100| TN["TrueNAS node-exporter<br/>10.212.4.150 - see machines/truenas.md"]
  PROM -->|"scrapes :3903/metrics, bearer"| GS["Garage on the NAS<br/>s3-k8s - see machines/truenas.md"]
  PROM -->|scrapes :9100 - :9221<br/>via metrics-allow-proxmox| PX["Proxmox hosts<br/>node-exporter + pve-exporter"]

  AM -->|critical: sound<br/>everything else: silent| TG["Telegram group"]
  AM -->|Watchdog, every 5m| HB["Cronitor heartbeat<br/>outside the lab, emails on silence"]

  GR -->|OIDC| PID["Pocket ID<br/>login.&lt;app_domain&gt; - see pocket-id.md"]
  GW["Gateway lab"] -->|grafana.&lt;app_domain&gt;| GR
  GW -->|alertmanager.&lt;app_domain&gt;| AM
```

Why it looks like this:

- **Retention 30d or 18GB**, whichever first, on a 20Gi `fast` PVC -- the size
  cap keeps the TSDB inside its volume; long history is not needed.
- **Dashboards:** the chart's own are off. Ours are JSON files flat in
  `infrastructure/configs/dashboards/`, each a `configMapGenerator` entry
  labelled `grafana_dashboard: "1"`; the sidecar picks them up in any
  namespace. Grafana is stateless (emptyDir), so the files are the truth.
- **Alertmanager secrets are mounted as files** (`kv/monitoring/alerting`:
  bot token, heartbeat URL) and read via `*_file` options; the Telegram chat
  id travels in `cluster-vars` -- no credential, but it names a private group.
- **Heartbeat is Cronitor**: `Watchdog` pings the URL the vault holds; when
  pings stop, Cronitor emails.
- **Every lab rule carries `origin: lab`**, which the chart's ~134 do not --
  the one matcher that finds or routes ours.
- **Prometheus selects across all namespaces** (`*SelectorNilUsesHelmValues:
  false`), so a ServiceMonitor, PodMonitor, ScrapeConfig or PrometheusRule
  beside its app is picked up.
- **Grafana's own alerting is unused**: a rule made in its UI dies with the
  pod.

Access, routing, alerts, dashboards and how to change them:
[Monitoring](../../docs/src/monitoring.md).
