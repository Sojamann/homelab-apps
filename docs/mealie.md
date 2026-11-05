# Mealie

Recipes, meal plans, shopping lists. One Deployment behind the Gateway, SSO
through Pocket ID, configured by env.

```mermaid
graph TD
  subgraph ml["ns: mealie"]
    ES["ExternalSecret mealie"] --> SEC[["Secret mealie<br/>OIDC_CLIENT_*"]]
    SRV["Deployment mealie<br/>Recreate - uid 1000"]
    SVC(["Service mealie<br/>:9000"])
    SRV --> SVC
    SEC -->|env| SRV
    DATA[/"PVC mealie-data<br/>RWO - fast - 5Gi"/] -->|/app/data| SRV
    RS["ReplicationSource mealie-data<br/>restic - daily"] -.->|clones| DATA
    HR["HTTPRoute mealie<br/>recipes.&lt;app_domain&gt;"] -->|:9000| SVC
  end

  HR -.->|parentRef| GW["Gateway lab<br/>platform layer"]
  BAO["OpenBao<br/>kv/mealie/app"] -.->|ClusterSecretStore openbao| ES
  SRV -.->|OIDC| PID["Pocket ID<br/>login.&lt;app_domain&gt;"]
  RS -->|see volsync.md| GA["Garage on the NAS<br/>k8s-backups"]

  classDef ext fill:#eee,stroke:#999,stroke-dasharray:3 3;
  class GW,BAO,PID,GA ext;
```

Why it looks like this:

- **One volume.** `mealie-data` holds the SQLite db, recipe images and the
  signing secrets Mealie generates on first start -- on `fast`, with a
  `backup.yaml` (see [volsync](./volsync.md)). Images are few and small; a
  split onto the NAS would buy two restores that must line up.
- **Config is env** in `server.yaml`; Mealie has no config file. Only the
  Pocket ID client is a secret.
- **Runs as uid 1000.** The entrypoint only `chown`s + `gosu`s when started as
  root, so the image runs unchanged.
- **No metrics**: Mealie exposes none. `/api/app/about` (the image's own
  healthcheck) is the probe.
- **One pod, `Recreate`**: SQLite has one writer and the data volume is RWO.

Pocket ID client, users, restore: [Mealie](../../docs/src/workloads/mealie.md).
