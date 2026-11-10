#!/bin/sh
# Copied, not mounted: a subPath mount into config/ makes kubelet create it as
# root, and the install can't write config.php.
set -eu
cp /lab/lab.config.php /var/www/html/config/lab.config.php
