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
    php -r '$parts = parse_url(getenv("DATABASE_URL")); if (!empty($parts["host"])) { echo $parts["host"] . ":" . ($parts["port"] ?? 3306); exit(0); } exit(1);'
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
    log "No database host found; running migrations without a TCP readiness check"
    return 0
  fi

  host="${target%:*}"
  port="${target##*:}"
  timeout="${DB_WAIT_TIMEOUT:-45}"
  interval="${DB_WAIT_INTERVAL:-3}"
  elapsed=0

  while [ "$elapsed" -lt "$timeout" ]; do
    if php -r '$host = $argv[1]; $port = (int) $argv[2]; $socket = @fsockopen($host, $port, $errno, $errstr, 2); if ($socket) { fclose($socket); exit(0); } exit(1);' "$host" "$port"; then
      log "Database reachable at $host:$port"
      return 0
    fi

    log "Waiting for database at $host:$port"
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  log "Database did not become reachable at $host:$port within ${timeout}s"
  return 1
}

./init --env=Production-Docker --overwrite=All
wait_for_db
./yii migrate --interactive=0

nginx -t
exec supervisord -c /etc/supervisor/conf.d/plugn-production.conf -n
