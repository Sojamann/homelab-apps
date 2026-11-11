# Memos

Note taking. One Deployment behind the Gateway, SSO through Pocket ID, the
instance settings declared in git.

```mermaid
graph TD
  subgraph mm["ns: memos"]
    ES["ExternalSecret memos"] --> SEC[["Secret memos<br/>ADMIN_PASSWORD - OIDC_CLIENT_*"]]
    CM[["ConfigMap memos-config-hash<br/>instance.json"]]
    SRV["Deployment memos<br/>Recreate - uid 1000<br/>applies instance.json on start"]
    SVC(["Service memos<br/>:5230"])
    SRV --> SVC
    SEC -->|env| SRV
    CM -->|/etc/memos/config| SRV
    DATA[/"PVC memos-data<br/>RWO - fast - 1Gi"/] -->|/var/opt/memos| SRV
    ASSETS[/"PVC memos-assets<br/>static PV - Retain"/] -->|/var/opt/memos/assets| SRV
    RS["ReplicationSource memos-data<br/>restic - daily"] -.->|clones| DATA
    HR["HTTPRoute memos<br/>notes.&lt;app_domain&gt;"] -->|:5230| SVC
  end

  HR -.->|parentRef| GW["Gateway lab<br/>platform layer"]
  BAO["OpenBao<br/>kv/memos/app"] -.->|ClusterSecretStore openbao| ES
  SRV -.->|OIDC| PID["Pocket ID<br/>login.&lt;app_domain&gt;"]
  ASSETS -.-> NAS["NAS<br/>slow/k8s-csi/memos<br/>hourly + daily snapshots"]
  RS -->|see volsync.md| GA["Garage on the NAS<br/>k8s-backups"]

  classDef ext fill:#eee,stroke:#999,stroke-dasharray:3 3;
  class GW,BAO,PID,NAS,GA ext;
```

Why it looks like this:

- **Two volumes.** `memos-data` (the SQLite db) is on
  `fast` with a `backup.yaml` -- see [volsync](./volsync.md).
  `memos-assets` (attachments) is a static `Retain` PV on
  `/mnt/slow/k8s-csi/memos`, mounted over `assets/` of the data dir, which is
  memos' default attachment path. The directory is made by hand -- see
  [machines/truenas.md](../../machines/truenas.md).
- **Git owns the instance settings.** `instance.json` (a
  `configMapGenerator`, so a change rolls the pod) is memos' declarative
  config: Pocket ID as identity provider, private access, password auth off,
  local attachment storage, the `admin` user. Applied on every start; the
  admin UI refuses to change what it declares. `$${env:X}` in it is the Flux
  escape for memos' own `${env:X}`.
- **Runs as uid 1000**, so the image's root entrypoint skips its `chown` +
  `su-exec`.
- **No metrics**: memos exposes none. `/healthz` (pings the db) is the probe.
- **One pod, `Recreate`**: SQLite has one writer and the data volume is RWO.

Pocket ID client, users, restore: [Memos](../../docs/src/workloads/memos.md).
