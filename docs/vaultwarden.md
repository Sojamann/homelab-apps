# Vaultwarden

Bitwarden-compatible password manager for the household.

```mermaid
graph TD
  subgraph vw["ns: vaultwarden"]
    ES["ExternalSecret vaultwarden"] --> SEC[["Secret vaultwarden<br/>admin-token"]]
    SRV["Deployment vaultwarden<br/>Recreate - uid 1000"]
    SRV --> SVC(["Service vaultwarden:8080"])
    PVC[/"PVC vaultwarden-data<br/>RWO - fast - 1Gi"/] -->|/data| SRV
    RS["ReplicationSource vaultwarden-data<br/>restic - daily"] -.->|clones| PVC
    SEC -->|ADMIN_TOKEN| SRV
    RT["HTTPRoute vaultwarden<br/>passwords.&lt;app_domain&gt; - timeout 0s"] -->|backendRef| SVC
  end

  BAO["OpenBao<br/>kv/vaultwarden/app"] -.->|ClusterSecretStore openbao| ES
  RS -->|see volsync.md| GA["Garage on the NAS<br/>k8s-backups"]
  RT -.->|parentRef| GW["Gateway lab<br/>ns gateway - platform layer"]

  classDef ext fill:#eee,stroke:#999,stroke-dasharray:3 3;
  class GW,BAO,GA ext;
```

Why it looks like this:

- **`fast`**: all of `/data` (`db.sqlite3`, `rsa_key.pem`, `attachments/`,
  `sends/`, `icon_cache/`) on a block device, so none of SQLite's NFS caveats
  apply. `fast` has no copy elsewhere, hence `backup.yaml` -- see
  [volsync](./volsync.md). One pod, `Recreate`.
- **`ADMIN_TOKEN`** is an argon2id hash from `kv/vaultwarden/app`, never the
  plaintext.
- **`SIGNUPS_ALLOWED=false`, `INVITATIONS_ALLOWED=true`**, no SMTP: an account
  exists only for an invited email.
- **`DOMAIN`** binds WebAuthn credentials to the URL; **`IP_HEADER:
  X-Forwarded-For`**, which Envoy appends, so rate limits see the real IP.
- **`timeout 0s` on the HTTPRoute**: Envoy's 15s default cuts off big
  attachments.

Accounts, the admin token, restore and updates:
[Vaultwarden](../../docs/src/workloads/vaultwarden.md).
