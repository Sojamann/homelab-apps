# Glance

Lab start page, upstream `glanceapp/glance`. No state, no secrets, no
storage.

```mermaid
graph TD
  subgraph gl["ns: glance"]
    CM[["ConfigMap glance-config-hash<br/>from glance.yml"]]
    SRV["Deployment glance<br/>uid 1000"]
    SRV --> SVC(["Service glance:8080"])
    CM -->|/app/config| SRV
    RT["HTTPRoute glance<br/>dash.&lt;app_domain&gt;"] -->|backendRef| SVC
  end

  RT -.->|parentRef| GW["Gateway lab<br/>ns gateway - platform layer"]
  SRV -->|releases| GH["GitHub API<br/>unauthenticated"]

  classDef ext fill:#eee,stroke:#999,stroke-dasharray:3 3;
  class GW,GH ext;
```

`apps/glance/glance.yml` goes through a `configMapGenerator`, so the
ConfigMap's name carries a content hash and an edit rolls the pod. Config,
release tracking, substitution gotchas and updates:
[Glance](../../docs/src/workloads/glance.md).
