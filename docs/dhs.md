# DHS

The DHS app runs on a public Hetzner box, not in the cluster: Ubuntu, docker
compose, postgres. The box opens nothing toward the lab, so the cluster pulls
from it over the tailnet -- a nightly `pg_dump` into a `fast` PVC that VolSync
backs up, and a scrape of its node_exporter. Both go through one tailscale
egress proxy -- see [tailscale](./tailscale.md).

```mermaid
graph TD
  subgraph d["ns: dhs"]
    ES["ExternalSecret postgres-backup"] --> SEC[["Secret<br/>PGUSER / PGPASSWORD"]]
    CJ["CronJob postgres-dump<br/>00:30 UTC"] --> PVC[/"PVC postgres-dump<br/>fast"/]
    SEC --> CJ
    RS["ReplicationSource<br/>01:00 UTC"] -.->|clones| PVC
    SVC(["Service dhs<br/>ExternalName"])
  end

  CJ -->|5432| SVC
  PROM["Prometheus<br/>ScrapeConfig dhs"] -->|9100| SVC
  SVC --> PX["tailscale proxy<br/>tag:k8s"]
  PX -->|WireGuard| BOX["dhs.&lt;tailnet&gt;<br/>tag:public, tag:dhs"]
  RS --> GA["Garage<br/>k8s-backups/dhs/postgres-dump"]
  BAO["OpenBao<br/>kv/dhs/backup"] -.-> ES

  classDef ext fill:#eee,stroke:#999,stroke-dasharray:3 3;
  class BOX,GA,BAO ext;
```

The dump is `-Fc`, the latest one only (`postgres.dump`); its history is
restic's -- see [volsync](./volsync.md). `dump.yaml`'s image tracks the
server's major (17): an older `pg_dump` refuses the server, a newer one writes
dumps the server's own `pg_restore` cannot read. Bump both together.

## Alerts

- `DhsDown` -- node_exporter unreachable for 5m: the box, its tailscale, or
  the proxy. Critical.
- `DhsDumpStale` -- no successful dump in 26h. Warning.

## The box

Not in this repo; done by hand:

- `tailscale up --advertise-tags=tag:public,tag:dhs` -- no `--ssh`
- Hetzner firewall: udp/41641 open, public 22 closed
- postgres published on loopback only (`127.0.0.1:5432:5432`), never
  `0.0.0.0` -- docker's rules bypass ufw; node_exporter likewise on
  `127.0.0.1:9100`
- tailscale forwards the two ports from the tailnet address, persisted in
  tailscaled's state:

  ```sh
  tailscale serve --bg --tcp 5432 tcp://127.0.0.1:5432
  tailscale serve --bg --tcp 9100 tcp://127.0.0.1:9100
  ```

  Nothing on the box listens beyond loopback, and the tailnet policy still
  decides who reaches the ports. Postgres sees every connection as
  `127.0.0.1`, so the password is the only guard past the policy.
- the backup role, whose name and password go in `secrets/vault.yml` as
  `dhs_backup_user` and `dhs_backup_password`:

  ```sql
  CREATE ROLE backup LOGIN PASSWORD '...';
  GRANT pg_read_all_data TO backup;
  ```

  The official image's `pg_hba.conf` already admits any host by password.

## Restore

Into a running postgres on the box, from a restored `postgres.dump`:

```sh
pg_restore --clean --if-exists -d postgres postgres.dump
```
