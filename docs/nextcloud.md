# Nextcloud

Files only: web UI, share links, desktop and mobile sync. The official apache
image, a CNPG Postgres, SSO through Pocket ID. Config is env plus one
git-owned config file and a start hook.

```mermaid
graph TD
  subgraph nc["ns: nextcloud"]
    ES["ExternalSecret nextcloud"] --> SEC[["Secret nextcloud<br/>admin pw, OIDC_CLIENT_*"]]
    CM[["ConfigMap nextcloud-config<br/>lab.config.php, hooks"]]
    SRV["Deployment nextcloud<br/>Recreate - uid 33<br/>+ cron sidecar, */5"]
    SVC(["Service nextcloud<br/>:80"])
    SRV --> SVC
    SEC -->|env| SRV
    CM -->|hooks| SRV
    HTML[/"PVC nextcloud-html<br/>RWO - fast - 5Gi"/] -->|/var/www/html| SRV
    DATA[/"PVC nextcloud-data<br/>static PV - NFS"/] -->|/var/www/html/data| SRV
    DB[("Cluster nextcloud-db<br/>CNPG, 1 instance, fast")]
    DBS[["Secret nextcloud-db-app<br/>by CNPG"]]
    DB --> DBS -->|env| SRV & DUMP
    SRV -->|nextcloud-db-rw:5432| DB
    DUMP["CronJob db-dump<br/>pg_dump 01:15"] --> DUMPV[/"PVC db-dump<br/>RWO - fast - 5Gi"/]
    RS["ReplicationSources<br/>db-dump, nextcloud-html"] -.->|clones| DUMPV & HTML
    HR["HTTPRoute nextcloud<br/>files.&lt;app_domain&gt;"] -->|:80| SVC
  end

  HR -.->|parentRef| GW["Gateway lab<br/>platform layer"]
  BAO["OpenBao<br/>kv/nextcloud/app"] -.->|ClusterSecretStore openbao| ES
  SRV -.->|OIDC| PID["Pocket ID<br/>login.&lt;app_domain&gt;"]
  RS -->|see volsync.md| GA["Garage on the NAS<br/>k8s-backups"]
  DATA -.-> NAS["NAS slow/k8s-csi/nextcloud<br/>ZFS snapshots"]

  classDef ext fill:#eee,stroke:#999,stroke-dasharray:3 3;
  class GW,BAO,PID,GA,NAS ext;
```

Why it looks like this:

- **Three stores.** Files on the NAS as a static `Retain` PV (like memos'
  attachments); `/var/www/html` on `fast` for code, `config.php` and apps;
  Postgres on `fast` through CNPG.
- **`lab.config.php`** is read after `config.php` and wins. A hook copies it
  into `config/` before install and on every start; a subPath mount would
  make kubelet create `config/` as root and break the install. It holds the db
  connection from env, so a rebuilt `Cluster` with a new CNPG password needs
  no edit. The ConfigMap has Flux substitution off: `$` there is PHP and
  shell, not Flux variables.
- **The start hook** (`before-starting`) runs on every start, after any
  install or upgrade: background jobs to cron, the unused default apps off,
  `user_oidc` installed and its provider written from env.
- **Runs as uid 33** (www-data) from the start, so the entrypoint skips its
  chown; `net.ipv4.ip_unprivileged_port_start=0` lets Apache keep port 80.
- **Background jobs** are a sidecar looping `cron.php` every 5 minutes: same
  version and node as the server, stops with it. Not the image's `/cron.sh`
  (busybox crond needs root), not a CronJob (would need the RWO volume's node,
  and runs mid-install/upgrade).
- **No Redis.** APCu (the image's default) for the local cache, the db for
  file locking -- enough for a household.
- **Backup** is a nightly `pg_dump` with CNPG's own image (same major), then
  VolSync, as for DHS. CNPG's backup feature is not used.

Users, break-glass, restore: [Nextcloud](../../docs/src/workloads/nextcloud.md).
