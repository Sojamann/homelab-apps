# Immich

Photo and video library -- phone backup, timeline, face and smart search.
LAN and NetBird only, like everything behind the gateway.

```mermaid
graph TD
  subgraph cnpg["ns: cnpg-system"]
    OP["CNPG operator"]
  end

  subgraph im["ns: immich"]
    PGC["Cluster immich-db<br/>1x pg 18.6-standard - sc fast 10Gi<br/>preload vchord.so"]
    VCH[("ImageVolume<br/>vchord-scratch:pg18-v1.1.1")] -->|extensions| PGC
    DB["Database immich<br/>vector - vchord - cube - earthdistance"] -->|CREATE EXTENSION| PGC
    PGC --> PGSVC(["Service immich-db-rw"])
    PGC --> PGSEC[["Secret immich-db-app<br/>username - password"]]

    VKD["Deployment valkey<br/>emptyDir"] --> VKSVC(["Service valkey:6379"])

    SRV["Deployment immich-server<br/>Recreate - uid 1000"]
    SRV --> SRVSVC(["Service immich-server:2283"])

    ML["Deployment immich-machine-learning<br/>Recreate - uid 1000 - mem limit 5Gi"]
    ML --> MLSVC(["Service immich-machine-learning:3003"])

    PVCM[/"PVC immich-media<br/>RWX - bulk - 500Gi label"/] -->|/data| SRV
    PVCF[/"PVC immich-fast<br/>RWO - fast - 20Gi"/] -->|/data/thumbs<br/>/data/encoded-video| SRV
    PVCC[/"PVC immich-cache<br/>RWO - fast - 10Gi"/] -->|/cache| ML

    PGSEC -->|secretKeyRef| SRV
    PGSVC -->|DB_HOSTNAME| SRV
    VKSVC -->|REDIS_HOSTNAME| SRV
    MLSVC -->|IMMICH_MACHINE_LEARNING_URL| SRV

    RT["HTTPRoute immich<br/>photos.$app_domain - timeout 0s"] -->|backendRef| SRVSVC
  end

  OP -.->|reconciles| PGC
  OP -.->|reconciles| DB
  RT -.->|parentRef| GW["Gateway lab<br/>ns gateway - platform layer"]

  classDef ext fill:#eee,stroke:#999,stroke-dasharray:3 3;
  class GW,OP ext;
```

## Storage

| PVC            | Class  | Holds                                   | Lost means                         |
|----------------|--------|-----------------------------------------|------------------------------------|
| `immich-media` | `bulk` | `library/` `upload/` `profile/` `backups/` | photos gone -- restore NAS snapshot |
| `immich-fast`  | `fast` | `thumbs/` `encoded-video/`              | re-run "Missing" thumbnail/transcode jobs |
| `immich-cache` | `fast` | ML models                               | re-download on next start          |
| CNPG `immich-db` | `fast` | albums, faces, EXIF, sharing          | **library structure gone** -- no backup |

`fast` zvols are thick: each PVC reserves its full size on the NVMe. Grow by
editing the request; never shrink.

Never mount `upload/` and `library/` separately -- Immich moves between them
by rename.

## Known gaps

- **No database backup.** Same as paperless. `fast` is one unmirrored NVMe with
  no snapshot task. Immich's own backup job needs superuser (`pg_dumpall`),
  which CNPG does not hand out, so it stays off.
- **Bootstrap reports failed once.** `immich-server` crash-loops until the
  `Database` has created the extensions; the Kustomization's retry clears it.

## First run

1. Open `https://photos.<app_domain>`, create the admin account -- the first
   user is admin, nothing is seeded.
2. *Administration -> Settings -> Machine Learning -> Smart Search*: set the
   CLIP model to `ViT-B-16-SigLIP-i18n-256__webli` (German and English
   queries, ~3 GB resident). Changing it later re-encodes the whole library.
3. *Administration -> Settings -> Backup*: leave database dumps disabled (see
   above).
4. Phones: join NetBird, then point the app at `https://photos.<app_domain>`.

## Upgrading

- `immich-server` and `immich-machine-learning` move together, same tag.
- Check the release notes' vchord range against `database.yaml` before a
  bump; bumping the `vchord-scratch` tag makes CNPG run `ALTER EXTENSION`.
