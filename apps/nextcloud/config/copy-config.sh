#!/bin/sh
# Copied, not mounted: a subPath mount into config/ makes kubelet create it as
# root, and the install can't write config.php.
set -eu
# install, not cp: cp keeps the ConfigMap's read-only mode, and the next
# start could not overwrite it.
install -m 0640 /lab/lab.config.php /var/www/html/config/lab.config.php
