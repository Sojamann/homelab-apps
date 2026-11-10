<?php
// Read after config.php on every request and wins over it. Mounted
// read-only; Nextcloud writes only config.php.
$CONFIG = [
  // From env, so a rebuilt db cluster (new CNPG password) needs no edit.
  'dbtype' => 'pgsql',
  'dbhost' => getenv('POSTGRES_HOST'),
  'dbname' => getenv('POSTGRES_DB'),
  'dbuser' => getenv('POSTGRES_USER'),
  'dbpassword' => getenv('POSTGRES_PASSWORD'),

  // Pocket ID resolves to the gateway's private address.
  'allow_local_remote_servers' => true,

  // New accounts start empty.
  'skeletondirectory' => '',
  'templatedirectory' => '',

  'default_phone_region' => 'DE',
  // Heavy background jobs between 01:00 and 05:00 UTC.
  'maintenance_window_start' => 1,
  // To stderr, so the log collector sees it.
  'log_type' => 'errorlog',
];
