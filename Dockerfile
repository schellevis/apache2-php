# PHP version can be overridden at build time:
#   docker build --build-arg PHP_VERSION=8.4 -t apache2-php .
ARG PHP_VERSION=8.4
ARG PHP_EXTENSIONS="bcmath curl dom exif gd gettext gmp intl mbstring mysqli opcache pcntl pdo pdo_mysql pdo_pgsql pdo_sqlite pgsql posix simplexml soap sockets xsl zip"

FROM php:${PHP_VERSION}-apache

ARG PHP_EXTENSIONS

LABEL org.opencontainers.image.title="apache2-php" \
      org.opencontainers.image.description="Apache2 + PHP with common extensions and Let's Encrypt support" \
      org.opencontainers.image.source="https://github.com/schellevis/apache2-php"

# Install system dependencies required for PHP extensions and certbot
RUN apt-get update && apt-get install -y --no-install-recommends \
        certbot \
        cron \
        libcap2-bin \
        libcurl4-openssl-dev \
        libfreetype6-dev \
        libgmp-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libonig-dev \
        libpng-dev \
        libpq-dev \
        libsqlite3-dev \
        libssl-dev \
        libwebp-dev \
        libxml2-dev \
        libxslt1-dev \
        libzip-dev \
        openssl \
        python3-certbot-apache \
        unzip \
        wget \
    && rm -rf /var/lib/apt/lists/*

# Configure GD with JPEG, WebP and FreeType support
RUN set -eux; \
    docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
        --with-webp; \
    docker-php-ext-install -j"$(nproc)" ${PHP_EXTENSIONS}

# Enable Apache modules
RUN a2enmod rewrite ssl headers expires deflate http2

# Harden Apache – suppress version info in HTTP headers and error pages
RUN { echo 'ServerTokens Prod'; echo 'ServerSignature Off'; } \
    > /etc/apache2/conf-available/security-hardening.conf \
    && a2enconf security-hardening

# Allow Apache to bind to ports 80/443 after the entrypoint drops privileges to www-data.
RUN setcap 'cap_net_bind_service=+ep' /usr/sbin/apache2 \
    && mkdir -p /var/run/apache2 /var/lock/apache2 /var/log/apache2 /var/www/letsencrypt \
    && chown -R www-data:www-data /var/run/apache2 /var/lock/apache2 /var/log/apache2 /var/www/letsencrypt

# Copy custom configuration files
COPY config/apache2/000-default.conf /etc/apache2/sites-available/000-default.conf
COPY config/apache2/ssl.conf         /etc/apache2/sites-available/ssl.conf
COPY config/php/php.ini              /usr/local/etc/php/conf.d/custom.ini
COPY scripts/entrypoint.sh           /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

# Expose HTTP and HTTPS ports
EXPOSE 80 443

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["apache2-foreground"]
