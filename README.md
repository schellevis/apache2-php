# apache2-php

Docker image combining **Apache 2** with the most recent **PHP versions**, a curated set of
popular PHP extensions, and built-in **Let's Encrypt / SSL** support.  
Images are built automatically via **GitHub Actions** and published to the
**GitHub Container Registry (ghcr.io)**.

---

## Table of contents

- [Quick start](#quick-start)
- [Available images](#available-images)
- [Environment variables](#environment-variables)
- [Let's Encrypt / SSL](#lets-encrypt--ssl)
- [PHP extensions included](#php-extensions-included)
- [Custom PHP configuration](#custom-php-configuration)
- [Building locally](#building-locally)
- [Project structure](#project-structure)
- [GitHub Actions CI/CD](#github-actions-cicd)
- [License](#license)

---

## Quick start

```bash
# Pull the latest image (PHP 8.4)
docker pull ghcr.io/schellevis/apache2-php:latest

# Run with your application mounted
docker run -d \
  -p 80:80 -p 443:443 \
  -v $(pwd)/www:/var/www/html \
  -e DOMAIN=example.com \
  ghcr.io/schellevis/apache2-php:latest
```

Or with `docker compose`:

```bash
docker compose up --build
```

---

## Available images

Images are pushed to `ghcr.io/schellevis/apache2-php`.

| Tag | PHP version |
|-----|-------------|
| `latest` | 8.4 (latest stable) |
| `php8.4` | 8.4 |
| `php8.3` | 8.3 |

Release tags (e.g. `v1.2.3`) are additionally suffixed: `v1.2.3-php8.3`.

---

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DOMAIN` | `localhost` | Fully-qualified domain name served by Apache |
| `EMAIL` | _(empty)_ | E-mail address used for Let's Encrypt registration |
| `USE_LETSENCRYPT` | `false` | Set to `true` to request/renew a Let's Encrypt certificate |
| `FORCE_HTTPS` | `false` | Set to `true` to redirect all HTTP → HTTPS (301) |

The extension set is controlled with a build arg:

| Variable | Default | Description |
|----------|---------|-------------|
| `PHP_EXTENSIONS` | `bcmath curl dom exif gd gettext gmp intl mbstring mysqli opcache pcntl pdo pdo_mysql pdo_pgsql pdo_sqlite pgsql posix simplexml soap sockets xsl zip` | Extensions compiled with `docker-php-ext-install` |

---

## Let's Encrypt / SSL

### Self-signed certificate (default)

When `USE_LETSENCRYPT=false` the container automatically generates a self-signed
certificate on first start so HTTPS is always available out of the box.

### Let's Encrypt certificate

Prerequisites:
- `DOMAIN` must point to your server's public IP (DNS A/AAAA record set)
- Ports **80** and **443** must be reachable from the internet

```bash
docker run -d \
  -p 80:80 -p 443:443 \
  -e DOMAIN=example.com \
  -e EMAIL=admin@example.com \
  -e USE_LETSENCRYPT=true \
  -e FORCE_HTTPS=true \
  -v letsencrypt:/etc/letsencrypt \
  ghcr.io/schellevis/apache2-php:latest
```

Certificates are automatically renewed twice daily via an in-container cron job.
Mount `/etc/letsencrypt` as a named volume to persist certificates across container restarts.

---

## PHP extensions included

| Extension(s) | Notes |
|---|---|
| bcmath, curl, dom, exif, gettext | general purpose |
| gd | JPEG + WebP + FreeType support |
| gmp | GNU Multiple Precision arithmetic |
| intl, mbstring | internationalisation / multibyte strings |
| mysqli, pdo, pdo_mysql, pdo_pgsql, pdo_sqlite, pgsql | databases |
| opcache | bytecode cache (enabled, JIT on) |
| pcntl, posix, sockets | process / OS / networking |
| simplexml, soap, xsl, zip | XML, SOAP, archives |

You can trim the extension set at build time:

```bash
docker build \
  --build-arg PHP_EXTENSIONS="bcmath gd intl mbstring mysqli opcache pdo pdo_mysql zip" \
  -t apache2-php:minimal .
```

---

## Custom PHP configuration

The image ships with sensible defaults in `config/php/php.ini` (copied to
`/usr/local/etc/php/conf.d/custom.ini`).  Key settings:

| Setting | Value |
|---------|-------|
| `memory_limit` | 256M |
| `upload_max_filesize` | 64M |
| `post_max_size` | 64M |
| `max_execution_time` | 120 |
| `date.timezone` | UTC |
| `opcache.jit` | enabled |

Override individual values by mounting your own ini file:

```bash
-v $(pwd)/my-overrides.ini:/usr/local/etc/php/conf.d/99-overrides.ini
```

---

## Building locally

```bash
# Default PHP version (8.4)
docker build -t apache2-php .

# Specific PHP version
docker build --build-arg PHP_VERSION=8.3 -t apache2-php:php8.3 .

# Minimal extension set
docker build \
  --build-arg PHP_EXTENSIONS="bcmath gd intl mbstring mysqli opcache pdo pdo_mysql zip" \
  -t apache2-php:minimal .
```

### docker compose

```bash
PHP_VERSION=8.4 docker compose up --build
```

Apache starts through the entrypoint with root only for certificate/bootstrap tasks and
then drops privileges before launching the web server process.

---

## Project structure

```
.
├── .github/
│   └── workflows/
│       └── build.yml          # Build & push to ghcr.io
├── config/
│   ├── apache2/
│   │   ├── 000-default.conf   # HTTP virtual host
│   │   └── ssl.conf           # HTTPS virtual host
│   └── php/
│       └── php.ini            # Custom PHP settings
├── scripts/
│   └── entrypoint.sh          # Container startup (SSL + certs)
├── docker-compose.yml
├── Dockerfile
├── CLAUDE.md
└── README.md
```

---

## GitHub Actions CI/CD

The workflow (`.github/workflows/build.yml`) triggers on:

- Push to `main`
- New version tag (`v*`)
- Weekly schedule (Sunday 02:00 UTC) – picks up base-image security patches

It builds **amd64** and **arm64** images for PHP versions **8.3, 8.4** in
parallel and pushes them to `ghcr.io`.

---

## License

MIT
