# Production Docker Runtime

Use the production compose file when validating the production Docker path:

```bash
docker compose -f docker-compose-prod.yml up --build
```

The production image now starts runtime services in the container entrypoint:

- installs optimized PHP dependencies during the Docker build
- initializes the `Production-Docker` environment
- waits for the configured database host before migrations, using
  `DB_HOST`/`DB_PORT`, `MYSQL_HOST`/`MYSQL_PORT`, `DATABASE_URL`, or the
  generated Yii DB DSN as the source
- runs Yii migrations non-interactively
- validates nginx configuration before starting nginx
- runs cron, nginx, and `php-fpm` under supervisord so failed runtime services
  are monitored instead of being left as untracked background daemons
- creates and owns the Yii runtime and upload directories as `www-data` before
  applying runtime permissions

The compose stack also waits for Redis health before starting the app, avoids
mounting the host source over the production image, and exposes an HTTP health
check that sends the `backend.plugn.io` host header so nginx tests the
application vhost rather than the default 404 server.

Database readiness can be tuned with `DB_WAIT_TIMEOUT` and `DB_WAIT_INTERVAL`
when the external database needs longer than the default startup window.
