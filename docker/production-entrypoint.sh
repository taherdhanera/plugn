#!/bin/sh
set -eu

./init --env=Production-Docker --overwrite=All
./yii migrate --interactive=0

nginx -t
cron
nginx

for process in cron nginx; do
  if ! pgrep -x "$process" >/dev/null 2>&1; then
    echo "ERROR: $process failed to start" >&2
    exit 1
  fi
done

exec php-fpm -F
