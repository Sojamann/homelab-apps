# Syncthing

The household's always-on sync hub. GUI over HTTPS on the Gateway, sync on
the Gateway's `syncthing` / `syncthing-quic` listeners (`:22000` tcp + udp).

```mermaid
graph TD
  subgraph st["ns: syncthing"]
    ES["ExternalSecret syncthing"] --> SEC[["Secret syncthing<br/>gui-password - api-key"]]
    INIT["init: syncthing generate<br/>keys once, GUI login every start"]
    SRV["Deployment syncthing<br/>Recreate - uid 1000<br/>postStart: options + folder defaults"]
    SVC(["Service syncthing<br/>:8384 GUI - :22000 tcp+udp sync"])
    SRV --> SVC
    CFG[/"PVC syncthing-config<br/>RWO - fast - 2Gi"/] -->|/var/syncthing/config| INIT & SRV
    DATA[/"PVC syncthing-data<br/>static PV - Retain"/] -->|/data| SRV
    RS["ReplicationSource syncthing-config<br/>restic - daily"] -.->|clones| CFG
    SEC --> INIT & SRV
    HR["HTTPRoute syncthing<br/>sync.&lt;app_domain&gt;"] -->|:8384| SVC
    TR["TCPRoute syncthing"] -->|:22000/tcp| SVC
    UR["UDPRoute syncthing-quic"] -->|:22000/udp| SVC
    SM["ServiceMonitor + PrometheusRule"] -.->|/metrics, bearer api-key| SVC
  end

  DEV["Windows - Mac - phones<br/>tcp:// + quic://sync.&lt;app_domain&gt;:22000"] -->|LAN or tailnet| GW
  HR & TR & UR -.->|parentRef| GW["Gateway lab<br/>https + syncthing :22000 tcp/udp<br/>platform layer"]
  BAO["OpenBao<br/>kv/syncthing/app"] -.->|ClusterSecretStore openbao| ES
  DATA -.-> NAS["NAS<br/>slow/k8s-csi/syncthing<br/>hourly + daily snapshots"]
  RS -->|see volsync.md| GA["Garage on the NAS<br/>k8s-backups"]

  classDef ext fill:#eee,stroke:#999,stroke-dasharray:3 3;
  class GW,BAO,GA,NAS,DEV ext;
```

Why it looks like this:

- **Two volumes, split by what SQLite tolerates.** `syncthing-data` (the
  files) is a static PV on `/mnt/slow/k8s-csi/syncthing` with `Retain`, not a
  `bulk` PVC: deleting the PVC, the namespace or the app leaves the directory,
  and a rebuild re-binds it by name. csi-driver-nfs only mkdirs what it
  provisions, so the directory is made by hand -- see
  [machines/truenas.md](../../machines/truenas.md). `syncthing-config` (keys,
  `config.xml`, index db) is on `fast` for SQLite, with a `backup.yaml` --
  see [volsync](./volsync.md).
- **Git owns part of the GUI's config.** The init container runs `syncthing
  generate` (keys once, GUI login every start); `postStart` re-applies the
  options (listen addresses, discovery/relays/NAT/reporting off, folder
  defaults: `/data/`, 7-day trash can). A GUI change to those is undone on
  restart. `STNOUPGRADE=1`: the tag in `server.yaml` is the version.
- **The TCP/UDP routes carry no hostname**: syncthing's TLS sends no SNI, so
  any name on the Gateway's address reaches `:22000`.
- **Metrics** are scraped with the API key as bearer token
  (`monitoring.yaml`, beside the rules).
- **One pod, `Recreate`**: SQLite has one writer and the config volume is RWO.

Folder layout, adding devices, restore and alerts:
[Syncthing](../../docs/src/workloads/syncthing.md).
