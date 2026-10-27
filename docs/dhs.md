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

Untested end to end; the dump itself is drilled (below). The box's postgres is
overwritten in place, so stop the app first.

1. **Pick the dump.** Last night's is still on `postgres-dump`. Anything older,
   or a lost PVC, comes out of restic: a `ReplicationDestination` with
   `copyMethod: Direct` into a new empty PVC, `restic.restoreAsOf` for a point
   in time -- see [volsync](./volsync.md#restore), and the drill below for a
   working example. Without the cluster, plain restic against
   `k8s-backups/dhs/postgres-dump`.
2. **Get it out of the cluster.** A pod mounting the PVC read-only, then:
   ```sh
   kubectl -n dhs run fetch --image=docker.io/library/busybox:1.37 --restart=Never \
     --overrides='{"spec":{"volumes":[{"name":"d","persistentVolumeClaim":{"claimName":"postgres-dump","readOnly":true}}],
       "containers":[{"name":"fetch","image":"docker.io/library/busybox:1.37","command":["sleep","3600"],
       "volumeMounts":[{"name":"d","mountPath":"/dump","readOnly":true}]}]}}'
   kubectl -n dhs cp fetch:/dump/postgres.dump ./postgres.dump
   kubectl -n dhs delete pod fetch
   ```
3. **Onto the box**, over the tailnet -- `group:admin` reaches `tag:public`:
   ```sh
   scp postgres.dump <user>@dhs.<tailnet>:
   ```
4. **Restore**, as the superuser, with the app stopped and postgres running.
   `--single-transaction`: it lands whole or not at all.
   ```sh
   docker compose stop <app>
   docker compose exec -T <postgres> \
     pg_restore -U postgres -d postgres --clean --if-exists --single-transaction < postgres.dump
   docker compose start <app>
   ```
   Flyway finds its history table restored with the data and migrates nothing.
5. **Check** row counts against the drill's query below.

On a fresh box: the dump holds no roles. The image creates `POSTGRES_USER` on
first start, which owns everything here; the backup role (above) has to be
created again. The server must be the dump's major (17) or newer.

## Drill

Run once on 2026-10-27, in `dhs`: a `ReplicationDestination` (`trigger.manual`,
`copyMethod: Direct`, uid 70) into a throwaway `fast` PVC `drill`, then a pod
on `postgres:17.11-alpine` that mounts it read-only, starts a socket-only
postgres in an `emptyDir` and restores into it:

```sh
initdb -D /tmp/pg
pg_ctl -D /tmp/pg -o "-k /tmp -c listen_addresses=''" -w start
createdb -h /tmp drill
pg_restore -h /tmp -d drill --no-owner --no-privileges --exit-on-error /restore/postgres.dump
psql -h /tmp -d drill -c "select schemaname, relname, n_live_tup from pg_stat_user_tables order by 1,2"
```

Result: clean restore, 12 tables (53 users, flyway at 5 migrations).
Afterwards `kubectl -n dhs delete pod/drill replicationdestination/drill pvc/drill`.
