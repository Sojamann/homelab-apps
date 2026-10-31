# Kassenbuch

Single-user Kassenbuch for the Verein. Image
`registry.<app_domain>/kassenbuch` from [zot](./zot.md), which allows
anonymous pulls, so there is no pull secret.

```mermaid
graph TD
  subgraph kb["ns: kassenbuch"]
    ES["ExternalSecret kassenbuch"] --> SEC[["Secret kassenbuch<br/>password-hash"]]
    SRV["Deployment kassenbuch<br/>Recreate - uid 1000"]
    SRV --> SVC(["Service kassenbuch:3000"])
    PVC[/"PVC kassenbuch-data<br/>RWX - bulk - 10Gi label"/] -->|/data| SRV
    SEC -->|KASSENBUCH_PASSWORD_HASH| SRV
    RT["HTTPRoute kassenbuch<br/>kassenbuch.&lt;app_domain&gt; - timeout 0s"] -->|backendRef| SVC
  end

  BAO["OpenBao<br/>kv/kassenbuch/app"] -.->|ClusterSecretStore openbao| ES
  RT -.->|parentRef| GW["Gateway lab<br/>ns gateway - platform layer"]

  classDef ext fill:#eee,stroke:#999,stroke-dasharray:3 3;
  class GW,BAO ext;
```

Why it looks like this:

- **`bulk`, not `fast`:** `/data` (`kassenbuch.db`, `belege/`, `exports/`)
  holds records with a retention duty, so it sits on the mirror under the NAS
  snapshots instead of the unmirrored NVMe. The 10Gi is a label.
- **One replica, `Recreate`:** SQLite on NFS holds only with one pod on one
  node over NFSv4.1.
- **`timeout 0s` on the HTTPRoute:** Envoy's 15s default cuts off large Beleg
  uploads and zip imports.
- **`KASSENBUCH_PASSWORD_HASH`** comes from `kv/kassenbuch/app` via the
  ExternalSecret; `ORIGIN` is plain env.

Password rotation, restore and updates:
[Kassenbuch](../../docs/src/workloads/kassenbuch.md).
