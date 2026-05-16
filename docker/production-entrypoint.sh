#!/bin/sh
set -eu

log() {
  printf '[production-entrypoint] %s\n' "$*"
}

resolve_db_target() {
  if [ -n "${DB_HOST:-}" ]; then
    printf '%s:%s\n' "$DB_HOST" "${DB_PORT:-3306}"
    return 0
  fi

  if [ -n "${MYSQL_HOST:-}" ]; then
    printf '%s:%s\n' "$MYSQL_HOST" "${MYSQL_PORT:-3306}"
    return 0
  fi

  if [ -n "${DATABASE_URL:-}" ]; then
    php <<'PHP'
<?php
$parts = parse_url(getenv('DATABASE_URL'));
if (!empty($parts['host'])) {
    echo $parts['host'] . ':' . ($parts['port'] ?? '3306');
    exit(0);
}
exit(1);
PHP
    return $?
  fi

  if [ -f common/config/main-local.php ]; then
    php <<'PHP'
<?php
$config = require 'common/config/main-local.php';
$dsn = $config['components']['db']['dsn'] ?? '';
if (preg_match('/host=([^;:]+)(?::([0-9]+))?/', $dsn, $matches)) {
    echo $matches[1] . ':' . ($matches[2] ?? '3306');
    exit(0);
}
exit(1);
PHP
    return $?
  fi

  return 1
}

wait_for_db() {
  target="$(resolve_db_target || true)"
  if [ -z "$target" ]; then
    log "No database host found; running migrations without a database readiness check"
    return 0
  fi

  host="${target%:*}"
  port="${target##*:}"
  timeout="${DB_WAIT_TIMEOUT:-45}"
  interval="${DB_WAIT_INTERVAL:-3}"
  elapsed=0

  while [ "$elapsed" -lt "$timeout" ]; do
    if php -r '
$host = $argv[1];
$port = (int) $argv[2];
$envUser = getenv("DB_USER") ?: getenv("DB_USERNAME") ?: getenv("MYSQL_USER");
$envPassword = getenv("DB_PASSWORD");
if ($envPassword === false) {
    $envPassword = getenv("MYSQL_PASSWORD");
}

$user = $envUser ?: "root";
$password = $envPassword === false ? "" : $envPassword;

if ((!$envUser || $envPassword === false) && ($databaseUrl = getenv("DATABASE_URL"))) {
    $parts = parse_url($databaseUrl);
    if (!$envUser && isset($parts["user"])) {
        $user = rawurldecode($parts["user"]);
    }
    if ($envPassword === false && isset($parts["pass"])) {
        $password = rawurldecode($parts["pass"]);
    }
}

if (is_file("common/config/main-local.php")) {
    $config = require "common/config/main-local.php";
    $db = $config["components"]["db"] ?? [];
    if (!$envUser && isset($db["username"])) {
        $user = $db["username"];
    }
    if ($envPassword === false && isset($db["password"])) {
        $password = $db["password"];
    }
}

try {
    $pdo = new PDO("mysql:host={$host};port={$port}", $user, $password, [
        PDO::ATTR_TIMEOUT => 2,
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    ]);
    $pdo->query("SELECT 1");
    exit(0);
} catch (Throwable $e) {
    exit(1);
}
' "$host" "$port"; then
      log "Database ready at $host:$port"
      return 0
    fi

    log "Waiting for database readiness at $host:$port"
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  log "Database did not become ready at $host:$port within ${timeout}s"
  return 1
}

./init --env=Production-Docker --overwrite=All
wait_for_db
./yii migrate --interactive=0

nginx -t
exec supervisord -c /etc/supervisor/conf.d/plugn-production.conf -n
