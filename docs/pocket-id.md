# Pocket ID

OIDC provider for the lab, passkeys only. In `infrastructure/controllers/`,
not `apps/`, so its Flux Kustomization is `infrastructure`.

```mermaid
graph TD
  subgraph pid["ns: pocket-id"]
    ES["ExternalSecret pocket-id"] --> SEC[["Secret pocket-id<br/>encryption-key"]]
    SRV["Deployment pocket-id<br/>Recreate - uid 1000"]
    SRV --> SVC(["Service pocket-id:1411"])
    PVC[/"PVC pocket-id-state<br/>RWO - fast - 1Gi"/] -->|/app/data| SRV
    SEC -->|ENCRYPTION_KEY_FILE| SRV
    RT["HTTPRoute pocket-id<br/>login.&lt;app_domain&gt;"] -->|backendRef| SVC
  end

  BAO["OpenBao<br/>kv/pocket-id/app"] -.->|ClusterSecretStore openbao| ES
  PVC -.-> SNAP["NAS<br/>fast/k8s-csi/vols<br/>hourly + daily snapshots"]
  RT -.->|parentRef| GW["Gateway lab<br/>ns gateway - platform layer"]

  classDef ext fill:#eee,stroke:#999,stroke-dasharray:3 3;
  class GW,BAO,SNAP ext;
```

Why it looks like this:

- **`fast`**: `pocket-id.db` (SQLite, WAL) and uploads on a block device, so
  none of SQLite's NFS caveats apply. One pod, `Recreate`.
- **`ENCRYPTION_KEY_FILE`** points at the Secret mount; the key is generated in
  `platform_secrets.tf` and the database is unreadable without it.

Users, clients, break-glass, restore and updates:
[Pocket ID](../../docs/src/platform/pocket-id.md).
