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

# ---- helpers ----------------------------------------------------------------

log() { echo "[entrypoint] $*"; }

generate_self_signed_cert() {
    log "Generating self-signed certificate for '${DOMAIN}' …"
    mkdir -p /etc/ssl/private /etc/ssl/certs
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "${SSL_KEY}" \
        -out    "${SSL_CERT}" \
        -subj   "/CN=${DOMAIN}" \
        2>/dev/null
    log "Self-signed certificate created."
}

enable_ssl_vhost() {
    a2ensite ssl.conf > /dev/null 2>&1 || true
}

# ---- Let's Encrypt / self-signed -------------------------------------------

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

    # Create webroot for ACME challenge (used during renewal)
    mkdir -p /var/www/letsencrypt/.well-known/acme-challenge

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

    # Symlink so Apache always finds certs at a fixed path
    mkdir -p /etc/ssl/private /etc/ssl/certs
    ln -sf "${CERT_PATH}" "${SSL_CERT}"
    ln -sf "${KEY_PATH}"  "${SSL_KEY}"

    # Install cron job for automatic renewal (twice daily, as recommended by EFF).
    # Webroot mode keeps Apache running during renewal; graceful reload picks up the new cert.
    cat > /etc/cron.d/certbot-renew <<'EOF'
0 0,12 * * * root certbot renew --quiet \
    --webroot -w /var/www/letsencrypt \
    --post-hook "apachectl -k graceful"
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
exec "$@"
