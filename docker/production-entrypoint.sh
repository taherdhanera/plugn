#!/bin/sh
set -eu

if [ ! -f vendor/autoload.php ]; then
  composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader
fi

./init --env=Production-Docker --overwrite=All
./yii migrate --interactive=0

nginx -t
service cron start
service nginx start

exec php-fpm -F
