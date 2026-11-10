#!/bin/sh
# before-starting hook: runs on every start, after install/upgrade. Idempotent.
set -eu
occ() { php /var/www/html/occ "$@"; }

occ background:cron

# Files only.
for app in activity contactsinteraction dashboard firstrunwizard \
  nextcloud_announcements photos recommendations related_resources \
  sharebymail support survey_client user_status weather_status app_api; do
  occ app:disable "$app" >/dev/null 2>&1 || true
done

occ app:install user_oidc >/dev/null 2>&1 || occ app:enable user_oidc
occ user_oidc:provider "Pocket ID" \
  --clientid="$OIDC_CLIENT_ID" \
  --clientsecret="$OIDC_CLIENT_SECRET" \
  --discoveryuri="$OIDC_DISCOVERY_URI" \
  --scope="openid email profile"
# Pocket ID is the only login; break-glass `admin` uses /login?direct=1.
occ config:app:set --type=string --value=0 user_oidc allow_multiple_user_backends
