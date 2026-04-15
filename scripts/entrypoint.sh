#!/bin/bash
# Entrypoint for the apache2-php container.
#
# Environment variables
# ---------------------
# DOMAIN            Fully-qualified domain name served by this container (default: localhost)
# EMAIL             E-mail address for Let's Encrypt registration (required for ACME)
# USE_LETSENCRYPT   Set to "true" to obtain/renew a Let's Encrypt certificate (default: false)
# FORCE_HTTPS       Set to "true" to redirect all HTTP → HTTPS traffic (default: false)

set -euo pipefail

DOMAIN="${DOMAIN:-localhost}"
EMAIL="${EMAIL:-}"
USE_LETSENCRYPT="${USE_LETSENCRYPT:-false}"
FORCE_HTTPS="${FORCE_HTTPS:-false}"

SSL_CERT="/etc/ssl/certs/apache-ssl.crt"
SSL_KEY="/etc/ssl/private/apache-ssl.key"
WWW_UID="$(id -u www-data)"
WWW_GID="$(id -g www-data)"

# ---- helpers ----------------------------------------------------------------

log() { echo "[entrypoint] $*"; }

prepare_runtime_dirs() {
    mkdir -p \
        /etc/ssl/private \
        /etc/ssl/certs \
        /var/run/apache2 \
        /var/lock/apache2 \
        /var/log/apache2 \
        /var/www/letsencrypt/.well-known/acme-challenge
    chown -R www-data:www-data /var/run/apache2 /var/lock/apache2 /var/log/apache2 /var/www/letsencrypt
}

sync_ssl_material() {
    install -m 0644 "${1}" "${SSL_CERT}"
    install -m 0640 -o root -g www-data "${2}" "${SSL_KEY}"
}

generate_self_signed_cert() {
    log "Generating self-signed certificate for '${DOMAIN}' …"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "${SSL_KEY}" \
        -out    "${SSL_CERT}" \
        -subj   "/CN=${DOMAIN}" \
        2>/dev/null
    chown root:www-data "${SSL_KEY}" "${SSL_CERT}"
    chmod 0640 "${SSL_KEY}"
    chmod 0644 "${SSL_CERT}"
    log "Self-signed certificate created."
}

enable_ssl_vhost() {
    a2ensite ssl.conf > /dev/null 2>&1 || true
}

# ---- Let's Encrypt / self-signed -------------------------------------------

prepare_runtime_dirs

if [ "${USE_LETSENCRYPT}" = "true" ]; then
    if [ -z "${EMAIL}" ]; then
        log "ERROR: EMAIL must be set when USE_LETSENCRYPT=true"
        exit 1
    fi
    if [ "${DOMAIN}" = "localhost" ]; then
        log "ERROR: DOMAIN must be a real FQDN when USE_LETSENCRYPT=true"
        exit 1
    fi

    CERT_PATH="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

    if [ ! -f "${CERT_PATH}" ]; then
        log "Requesting Let's Encrypt certificate for '${DOMAIN}' …"
        certbot certonly \
            --standalone \
            --non-interactive \
            --agree-tos \
            --email  "${EMAIL}" \
            --domain "${DOMAIN}"
    else
        log "Existing Let's Encrypt certificate found – skipping initial request."
    fi

    sync_ssl_material "${CERT_PATH}" "${KEY_PATH}"

    # Install cron job for automatic renewal (twice daily, as recommended by EFF).
    # Webroot mode keeps Apache running during renewal; the deploy hook refreshes the copied certs.
    cat > /etc/cron.d/certbot-renew <<EOF
0 0,12 * * * root certbot renew --quiet \
    --webroot -w /var/www/letsencrypt \
    --deploy-hook "install -m 0644 ${CERT_PATH} ${SSL_CERT} && install -m 0640 -o root -g www-data ${KEY_PATH} ${SSL_KEY} && apachectl -k graceful"
EOF
    chmod 0644 /etc/cron.d/certbot-renew
    service cron start || true
    log "Let's Encrypt certificate configured; auto-renewal cron installed."

else
    generate_self_signed_cert
fi

enable_ssl_vhost

# Export FORCE_HTTPS so Apache's mod_rewrite can read it via %{ENV:FORCE_HTTPS}
if [ "${FORCE_HTTPS}" = "true" ]; then
    export FORCE_HTTPS=true
else
    export FORCE_HTTPS=false
fi

log "Starting Apache (PHP ${PHP_VERSION:-unknown}) …"
if [ "$#" -gt 0 ] && [ "$1" = "apache2-foreground" ]; then
    exec setpriv --reuid="${WWW_UID}" --regid="${WWW_GID}" --init-groups "$@"
fi

exec "$@"
