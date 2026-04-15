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

### Built-in extensions

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

### PECL extensions (enabled by default)

| Extension | Notes |
|---|---|
| apcu | in-memory user cache |
| igbinary | fast binary serializer – used by redis & memcached |
| imagick | ImageMagick image manipulation |
| memcached | Memcached client (igbinary serializer enabled) |
| mongodb | MongoDB driver |
| redis | Redis client (igbinary serializer enabled) |
| swoole | Async PHP runtime (OpenSSL enabled) |

### PECL extensions (installed, NOT enabled by default)

These are available in the image but must be explicitly enabled, typically only in
development environments, because they impact runtime performance.

| Extension | How to enable |
|---|---|
| xdebug | `echo "zend_extension=xdebug" > /usr/local/etc/php/conf.d/xdebug.ini` |
| pcov | `echo "extension=pcov" > /usr/local/etc/php/conf.d/pcov.ini` |

> **Note:** xdebug uses `zend_extension` (it hooks into the Zend Engine); pcov uses the
> standard `extension` directive.

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
```

### docker compose

```bash
PHP_VERSION=8.4 docker compose up --build
```

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