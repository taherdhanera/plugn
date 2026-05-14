# Production Docker Runtime

Use the production compose file when validating the production Docker path:

```bash
docker compose -f docker-compose-prod.yml up --build
```

The production image now starts runtime services in the container entrypoint:

- installs optimized PHP dependencies during the Docker build
- initializes the `Production-Docker` environment
- runs Yii migrations non-interactively
- validates nginx configuration before starting nginx
- starts cron at container runtime
- fails fast if nginx or cron do not start
- runs `php-fpm` in the foreground so Docker can track the application process

The compose stack also waits for Redis health before starting the app, avoids
mounting the host source over the production image, and exposes an HTTP health
check that sends the `backend.plugn.io` host header so nginx tests the
application vhost rather than the default 404 server.
