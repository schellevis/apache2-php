# PHP version can be overridden at build time:
#   docker build --build-arg PHP_VERSION=8.4 -t apache2-php .
ARG PHP_VERSION=8.4

FROM php:${PHP_VERSION}-apache

LABEL org.opencontainers.image.title="apache2-php" \
      org.opencontainers.image.description="Apache2 + PHP with common extensions and Let's Encrypt support" \
      org.opencontainers.image.source="https://github.com/schellevis/apache2-php"

# Install system dependencies required for PHP extensions and certbot
RUN apt-get update && apt-get install -y --no-install-recommends \
        certbot \
        cron \
        libcurl4-openssl-dev \
        libfreetype6-dev \
        libgmp-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libmagickwand-dev \
        libmemcached-dev \
        libonig-dev \
        libpng-dev \
        libpq-dev \
        libssl-dev \
        libwebp-dev \
        libxml2-dev \
        libxslt1-dev \
        libzip-dev \
        libzstd-dev \
        openssl \
        python3-certbot-apache \
        unzip \
        wget \
    && rm -rf /var/lib/apt/lists/*

# Configure GD with JPEG, WebP and FreeType support
RUN docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
        --with-webp

# Install PHP extensions
RUN docker-php-ext-install -j"$(nproc)" \
        bcmath \
        curl \
        dom \
        exif \
        gd \
        gettext \
        gmp \
        intl \
        mbstring \
        mysqli \
        opcache \
        pcntl \
        pdo \
        pdo_mysql \
        pdo_pgsql \
        pdo_sqlite \
        pgsql \
        posix \
        simplexml \
        soap \
        sockets \
        xsl \
        zip

# Install igbinary first – used as a faster serializer by redis and memcached
RUN pecl install igbinary \
    && docker-php-ext-enable igbinary

# Install remaining PECL extensions
# redis and memcached are built with igbinary support (igbinary must be installed first)
RUN pecl install apcu \
    && pecl install -D 'enable-redis-igbinary="yes"' redis \
    && pecl install -D 'enable-memcached-igbinary="yes"' memcached \
    && pecl install mongodb \
    && pecl install imagick \
    && pecl install -D 'enable-swoole-openssl="yes"' swoole \
    && docker-php-ext-enable apcu redis memcached mongodb imagick swoole opcache

# Install development-only PECL extensions – NOT enabled by default.
# Enable in development by adding a volume-mounted ini file, e.g.:
#   echo "zend_extension=xdebug" > /usr/local/etc/php/conf.d/xdebug.ini
#   echo "extension=pcov"        > /usr/local/etc/php/conf.d/pcov.ini
RUN pecl install xdebug pcov

# Enable Apache modules
RUN a2enmod rewrite ssl headers expires deflate http2

# Harden Apache – suppress version info in HTTP headers and error pages
RUN { echo 'ServerTokens Prod'; echo 'ServerSignature Off'; } \
    > /etc/apache2/conf-available/security-hardening.conf \
    && a2enconf security-hardening

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
