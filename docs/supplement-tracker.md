# Supplement tracker

The household's supplement plan. Image
`registry.<app_domain>/supplement-tracker` from [zot](./zot.md), which allows
anonymous pulls, so there is no pull secret. No secrets, so no
ExternalSecret.

```mermaid
graph TD
  subgraph st["ns: supplement-tracker"]
    SRV["Deployment supplement-tracker<br/>Recreate - uid 1000"]
    SRV --> SVC(["Service supplement-tracker:3000"])
    PVC[/"PVC supplement-tracker-data<br/>RWX - bulk - 1Gi label"/] -->|/data| SRV
    RT["HTTPRoute supplement-tracker<br/>supplements.&lt;app_domain&gt;"] -->|backendRef| SVC
  end

  RT -.->|parentRef| GW["Gateway lab<br/>ns gateway - platform layer"]

  classDef ext fill:#eee,stroke:#999,stroke-dasharray:3 3;
  class GW ext;
```

Why it looks like this:

- **`bulk`:** `/data` holds only `supplements.db` (SQLite, WAL), and the app
  has no export, so the NAS snapshots are its only backup. The 1Gi is a label.
- **One replica, `Recreate`:** SQLite on NFS holds only with one pod on one
  node over NFSv4.1.
- **Probes hit `/healthz`**, which runs a query. `ORIGIN` is the only env.

Restore and updates:
[Supplement tracker](../../docs/src/workloads/supplement-tracker.md).
