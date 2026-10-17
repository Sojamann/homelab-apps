# Pocket ID

OIDC provider for the lab, passkeys only. An extra way in, not the only one:
every app keeps its own admin login as break-glass, so Pocket ID being down
locks nobody out. Served at `login.${app_domain}`, LAN and tailnet only.

```mermaid
graph TD
  subgraph pid["ns: pocket-id"]
    ES["ExternalSecret pocket-id"] --> SEC[["Secret pocket-id<br/>encryption-key"]]
    SRV["Deployment pocket-id<br/>Recreate - uid 1000"]
    SRV --> SVC(["Service pocket-id:1411"])
    PVC[/"PVC pocket-id-state<br/>RWO - fast - 1Gi"/] -->|/app/data| SRV
    SEC -->|ENCRYPTION_KEY_FILE| SRV
    RT["HTTPRoute pocket-id<br/>login.$app_domain"] -->|backendRef| SVC
  end

  BAO["OpenBao<br/>kv/pocket-id/app"] -.->|ClusterSecretStore openbao| ES
  RT -.->|parentRef| GW["Gateway lab<br/>ns gateway - platform layer"]

  classDef ext fill:#eee,stroke:#999,stroke-dasharray:3 3;
  class GW,BAO ext;
```

## Storage

One `fast` PVC for `/app/data`: `pocket-id.db` (SQLite, WAL) and uploads. A
block device, so none of SQLite's NFS caveats apply.

`fast` is one unmirrored NVMe with no snapshot task: losing it means every
passkey enrolled again and every client re-registered. Accepted until the
second NVMe mirrors the pool; the apps' admin logins cover the gap.

Moving it between PVCs (how it came off `bulk`):

1. `flux suspend ks infrastructure`, scale `deploy/pocket-id` to 0
2. apply the new PVC and a pod mounting both; `cp -a` old to new
3. annotate the old PVC `kustomize.toolkit.fluxcd.io/prune=disabled`
4. point `claimName` at the new PVC, push, `flux resume ks infrastructure`
5. delete the old PVC by hand once logins work

The encryption key is generated in `platform_secrets.tf`; the database is
unreadable without it, and the tofu state is its backup.

## First start

`/setup` creates the first admin -- whoever opens it first. Do it right after
the first deploy.

## Users

No signups and no SMTP. Users and groups are created in the admin UI; each
person gets a one-time login link and enrolls a passkey with it.

| Group       | Meaning                       |
|-------------|-------------------------------|
| `admins`    | admin in the apps that map it |
| `household` | everyone else                 |

A lost passkey: issue a new one-time link. Your own admin passkey lost:

```sh
kubectl -n pocket-id exec deploy/pocket-id -- /app/pocket-id one-time-access-token <username>
```

## Clients

Registered by hand in the admin UI. The secret goes to OpenBao only when the
app reads its OIDC settings from config rather than its own database:

ansible vault -> `platform_secrets.tf` -> `kv/<ns>/<app>` -> `ExternalSecret`

Losing a client secret costs a re-registration, not access.

## Updates

The image tag is pinned; Renovate proposes bumps.
