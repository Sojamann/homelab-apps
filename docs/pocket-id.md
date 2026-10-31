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
    RS["ReplicationSource pocket-id-state<br/>restic - daily<br/>from infrastructure/configs"] -.->|clones| PVC
    SEC -->|ENCRYPTION_KEY_FILE| SRV
    RT["HTTPRoute pocket-id<br/>login.&lt;app_domain&gt;"] -->|backendRef| SVC
  end

  BAO["OpenBao<br/>kv/pocket-id/app"] -.->|ClusterSecretStore openbao| ES
  RS -->|see volsync.md| GA["Garage on the NAS<br/>k8s-backups"]
  RT -.->|parentRef| GW["Gateway lab<br/>ns gateway - platform layer"]

  classDef ext fill:#eee,stroke:#999,stroke-dasharray:3 3;
  class GW,BAO,GA ext;
```

Why it looks like this:

- **`fast`**: `pocket-id.db` (SQLite, WAL) and uploads on a block device, so
  none of SQLite's NFS caveats apply. One pod, `Recreate`.
- **The ReplicationSource is in `infrastructure/configs/pocket-id/`**, not
  beside the app: this directory is applied in the same pass as the VolSync
  chart, and a CR cannot be applied with the chart that defines its kind.
  Pattern: [volsync](./volsync.md).
- **`ENCRYPTION_KEY_FILE`** points at the Secret mount; the key is generated in
  `platform_secrets.tf` and the database is unreadable without it.

Users, clients, break-glass, restore and updates:
[Pocket ID](../../docs/src/platform/pocket-id.md).
