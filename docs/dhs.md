# DHS

The DHS app runs on a public Hetzner box, not in the cluster: Ubuntu, docker
compose, postgres. The box opens nothing toward the lab, so the cluster pulls
from it over the tailnet -- a nightly `pg_dump` into a `fast` PVC, which the
NAS snapshots, and a scrape of its node_exporter. Both go through one tailscale
egress proxy -- see [tailscale](./tailscale.md).

```mermaid
graph TD
  subgraph d["ns: dhs"]
    ES["ExternalSecret postgres-backup"] --> SEC[["Secret<br/>PGUSER / PGPASSWORD"]]
    CJ["CronJob postgres-dump<br/>00:30 UTC"] --> PVC[/"PVC postgres-dump<br/>fast"/]
    SEC --> CJ
    SVC(["Service dhs<br/>ExternalName"])
  end

  CJ -->|5432| SVC
  PROM["VMAgent<br/>VMScrapeConfig dhs"] -->|9100| SVC
  SVC --> PX["tailscale proxy<br/>tag:k8s"]
  PX -->|WireGuard| BOX["dhs.&lt;tailnet&gt;<br/>tag:public, tag:dhs"]
  PVC -.-> SNAP["NAS<br/>fast/k8s-csi/vols<br/>hourly + daily snapshots"]
  BAO["OpenBao<br/>kv/dhs/backup"] -.-> ES

  classDef ext fill:#eee,stroke:#999,stroke-dasharray:3 3;
  class BOX,SNAP,BAO ext;
```

Why it looks like this:

- **The dump is written aside** (`postgres.dump.tmp`, `sync`, `mv`): an
  hourly NAS snapshot must never catch a half-written file. `-Fc`, the latest
  one only; its history is the snapshots'.
- **The dump runs as uid 70**, postgres in the alpine image.
- **`dump.yaml`'s image tracks the server's major (17):** an older `pg_dump`
  refuses the server, a newer one writes dumps the server's own `pg_restore`
  cannot read. Bump both together.
- **`egress.yaml` names both ports**, but the proxy forwards every port; the
  tailnet policy is what limits `tag:k8s` to 5432 and 9100.
- **`scrape.yaml` relabels `instance` to `dhs`** -- the target address is only
  the proxy Service's name -- and `job` to `dhs`, which a `VMScrapeConfig`
  has no field for. It sits in `monitoring`, beside VMAgent, and
  `rules.yaml` carries `DhsDown` / `DhsDumpStale`.

The box's setup, the backup role, alerts and the restore:
[DHS](../../docs/src/workloads/dhs.md).
