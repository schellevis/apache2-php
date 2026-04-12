# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with this repository.

---

## Project overview

**apache2-php** is a Docker image that combines:

- **Apache 2** (mod_rewrite, mod_ssl, mod_headers, mod_http2, …)
- **PHP** – version selected at build time via `ARG PHP_VERSION` (default `8.3`)
- A curated set of common PHP extensions (bcmath, gd, intl, mbstring, pdo_mysql,
  pdo_pgsql, redis, apcu, …)
- **Let's Encrypt** / certbot support with automatic certificate renewal
- Multi-architecture images published to **ghcr.io** via GitHub Actions

---

## Repository structure

```
.
├── .github/
│   └── workflows/
│       └── build.yml          # CI: build multi-version images & push to ghcr.io
├── config/
│   ├── apache2/
│   │   ├── 000-default.conf   # HTTP virtual host (port 80, ACME challenge)
│   │   └── ssl.conf           # HTTPS virtual host (port 443, modern TLS)
│   └── php/
│       └── php.ini            # Custom PHP ini (copied to conf.d/custom.ini)
├── scripts/
│   └── entrypoint.sh          # Container entrypoint – generates/fetches TLS certs,
│                              #   enables SSL vhost, then exec's apache2-foreground
├── docker-compose.yml         # Local development helper
├── Dockerfile                 # Main image definition
├── CLAUDE.md                  # ← you are here
└── README.md                  # End-user documentation
```

---

## Build commands

```bash
# Build with default PHP version (8.3)
docker build -t apache2-php .

# Build with a specific PHP version
docker build --build-arg PHP_VERSION=8.4 -t apache2-php:php8.4 .

# Build and run locally with docker compose
docker compose up --build

# Build for a specific PHP version via compose
PHP_VERSION=8.2 docker compose up --build
```

---

## Run / test commands

```bash
# Run with self-signed TLS (default)
docker run --rm -p 80:80 -p 443:443 apache2-php

# Run with custom domain and self-signed cert
docker run --rm -p 80:80 -p 443:443 \
  -e DOMAIN=example.local \
  apache2-php

# Run with Let's Encrypt (requires real domain + public IP on 80/443)
docker run -d \
  -p 80:80 -p 443:443 \
  -e DOMAIN=example.com \
  -e EMAIL=admin@example.com \
  -e USE_LETSENCRYPT=true \
  -e FORCE_HTTPS=true \
  -v letsencrypt:/etc/letsencrypt \
  apache2-php

# Verify PHP version inside a running container
docker exec <container> php -v

# List enabled PHP extensions
docker exec <container> php -m
```

---

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DOMAIN` | `localhost` | FQDN served by Apache |
| `EMAIL` | _(empty)_ | E-mail for Let's Encrypt |
| `USE_LETSENCRYPT` | `false` | Obtain a real cert via ACME |
| `FORCE_HTTPS` | `false` | Redirect HTTP → HTTPS |

---

## Key design decisions

### PHP version via build ARG
The PHP version is a **build-time** argument (`ARG PHP_VERSION`), not a runtime env var,
because the PHP binary itself is baked into the image layer.  
The GitHub Actions matrix builds separate images for each supported version (8.1–8.4).

### TLS certificate handling (entrypoint.sh)
1. If `USE_LETSENCRYPT=true` – run `certbot certonly --standalone` on first boot,
   then symlink certs to `/etc/ssl/certs/apache-ssl.crt` and `/etc/ssl/private/apache-ssl.key`.
   A cron job handles automatic renewal.
2. Otherwise – generate a **self-signed** certificate at startup so HTTPS always works.

### Apache virtual hosts
- `000-default.conf` handles HTTP (port 80) and the ACME `.well-known` challenge path.
- `ssl.conf` handles HTTPS (port 443) with a modern cipher suite and HSTS header.
  It is enabled dynamically by the entrypoint.

### Image tagging strategy (GitHub Actions)
| Trigger | Tags produced |
|---------|---------------|
| Push to `main` | `main-php8.3`, `php8.3` |
| Tag `v1.2.3` | `v1.2.3-php8.3`, `1.2-php8.3`, `php8.3` |
| PHP 8.4 on default branch | additionally `latest` |

---

## Extending the image

### Adding a PHP extension

```dockerfile
FROM ghcr.io/schellevis/apache2-php:php8.3
RUN docker-php-ext-install pdo_sqlite
```

### Adding a PECL extension

```dockerfile
FROM ghcr.io/schellevis/apache2-php:php8.3
RUN pecl install imagick && docker-php-ext-enable imagick
```

### Custom Apache vhost

```dockerfile
FROM ghcr.io/schellevis/apache2-php:php8.3
COPY my-vhost.conf /etc/apache2/sites-available/my-vhost.conf
RUN a2ensite my-vhost.conf
```

---

## CI / GitHub Actions

Workflow file: `.github/workflows/build.yml`

- Triggered on: push to `main`, version tags (`v*`), weekly schedule (Sun 02:00 UTC),
  and manual `workflow_dispatch`.
- Builds `linux/amd64` and `linux/arm64` via QEMU + Buildx.
- Uses GitHub Actions cache (`type=gha`) scoped per PHP version.
- Pushes to `ghcr.io` using `GITHUB_TOKEN` (no extra secrets required).

To trigger a manual build:  
`Actions → Build and push Docker image → Run workflow`
