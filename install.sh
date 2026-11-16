#!/usr/bin/env bash
# One-shot installer for a fresh Ubuntu 22.04/24.04/26.04 x86-64 server:
#   Headwind MDM + Headwind Remote (aPuppet) behind the host nginx with Let's Encrypt.
# Safe to re-run: it keeps existing secrets, data and certificates.
#
#   sudo ./install.sh            # full install / update configs
#   sudo ./install.sh --no-ufw   # don't touch the firewall
set -euo pipefail
cd "$(dirname "$0")"
INSTALL_DIR="$(pwd)"
USE_UFW=1
[[ "${1:-}" == "--no-ufw" ]] && USE_UFW=0

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root (sudo ./install.sh)"
[[ "$(uname -m)" == "x86_64" ]] || die "x86-64 only (the Headwind images are amd64)"
[[ -f .env ]] || die "copy .env.example to .env and set MDM_DOMAIN, REMOTE_DOMAIN, ADMIN_EMAIL"

# ---------------------------------------------------------------- settings
set -a; . ./.env; set +a
for v in MDM_DOMAIN REMOTE_DOMAIN ADMIN_EMAIL; do
  [[ -n "${!v:-}" && "${!v}" != *example.com ]] || die "set $v in .env"
done

gen() { tr -dc 'A-HJ-NP-Za-km-z2-9' < /dev/urandom | head -c "$1"; }
set_env() { # set_env KEY VALUE: write back to .env
  if grep -q "^$1=" .env; then sed -i "s|^$1=.*|$1=$2|" .env; else echo "$1=$2" >> .env; fi
  export "$1=$2"
}
[[ -n "${SQL_PASS:-}" ]]           || set_env SQL_PASS "$(gen 32)"
[[ -n "${SHARED_SECRET:-}" ]]      || set_env SHARED_SECRET "$(gen 32)"
[[ -n "${JANUS_API_SECRET:-}" ]]   || set_env JANUS_API_SECRET "$(gen 24)"
[[ -n "${JANUS_ADMIN_SECRET:-}" ]] || set_env JANUS_ADMIN_SECRET "$(gen 32)"
[[ -n "${REMOTE_ADMIN_USER:-}" ]]  || set_env REMOTE_ADMIN_USER support
[[ -n "${REMOTE_ADMIN_PASS:-}" ]]  || set_env REMOTE_ADMIN_PASS "$(gen 20)"
if [[ -z "${PUBLIC_IP:-}" ]]; then
  set_env PUBLIC_IP "$(curl -4fsS https://api.ipify.org || curl -4fsS https://ifconfig.me)"
fi
chmod 600 .env
export INSTALL_DIR

# DNS must already point here, or certbot fails.
for d in "$MDM_DOMAIN" "$REMOTE_DOMAIN"; do
  ip="$(getent ahostsv4 "$d" | awk 'NR==1{print $1}')"
  [[ "$ip" == "$PUBLIC_IP" ]] || die "$d resolves to '${ip:-nothing}', expected $PUBLIC_IP. Fix DNS and retry."
done

# ---------------------------------------------------------------- packages
log "Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gettext-base nginx certbot apache2-utils ufw unattended-upgrades >/dev/null
if ! command -v docker >/dev/null; then
  log "Installing Docker (official convenience script)"
  curl -fsSL https://get.docker.com | sh >/dev/null
fi
docker compose version >/dev/null || die "docker compose plugin missing"
systemctl enable --now docker >/dev/null

# ---------------------------------------------------------------- swap
if [[ "${SWAP_SIZE:-0}" != "0" ]] && ! swapon --show | grep -q .; then
  log "Creating ${SWAP_SIZE} swap file"
  fallocate -l "$SWAP_SIZE" /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  sysctl -qw vm.swappiness=10
  echo 'vm.swappiness=10' > /etc/sysctl.d/99-remote-support.conf
fi

# ---------------------------------------------------------------- firewall
if [[ $USE_UFW -eq 1 ]]; then
  log "Firewall: SSH, HTTP(S), MDM push 31000/tcp, RTP ${RTP_PORT_RANGE}/udp"
  ufw allow OpenSSH >/dev/null
  ufw allow 80/tcp >/dev/null
  ufw allow 443/tcp >/dev/null
  ufw allow 31000/tcp >/dev/null
  ufw allow "${RTP_PORT_RANGE/-/:}/udp" >/dev/null
  ufw --force enable >/dev/null
fi

# ---------------------------------------------------------------- certificates
log "TLS certificates"
mkdir -p /var/www/certbot /etc/nginx/snippets
cp nginx/remote-support-tls.conf /etc/nginx/snippets/remote-support-tls.conf
rm -f /etc/nginx/sites-enabled/default
VARS='${MDM_DOMAIN} ${REMOTE_DOMAIN} ${INSTALL_DIR}'
need_cert() { [[ ! -f "/etc/letsencrypt/live/$1/fullchain.pem" ]]; }
if need_cert "$MDM_DOMAIN" || need_cert "$REMOTE_DOMAIN"; then
  envsubst "$VARS" < nginx/acme-bootstrap.conf.tmpl > /etc/nginx/sites-available/remote-support-acme.conf
  ln -sf /etc/nginx/sites-available/remote-support-acme.conf /etc/nginx/sites-enabled/
  nginx -t -q && systemctl reload nginx
  for d in "$MDM_DOMAIN" "$REMOTE_DOMAIN"; do
    need_cert "$d" && certbot certonly --webroot -w /var/www/certbot -d "$d" \
      --non-interactive --agree-tos -m "$ADMIN_EMAIL" --no-eff-email
  done
  rm -f /etc/nginx/sites-enabled/remote-support-acme.conf /etc/nginx/sites-available/remote-support-acme.conf
fi
# Reload nginx after renewals; the MDM rebuilds its keystore on restart (update.sh).
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
install -m 755 /dev/stdin /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh <<'EOF'
#!/bin/sh
systemctl reload nginx
EOF

# ---------------------------------------------------------------- configs
log "Rendering configs"
mkdir -p generated/janus data
for f in remote/janus/*.tmpl; do
  envsubst '${JANUS_API_SECRET} ${JANUS_ADMIN_SECRET} ${RTP_PORT_RANGE} ${PUBLIC_IP} ${REMOTE_DOMAIN}' \
    < "$f" > "generated/janus/$(basename "$f" .tmpl)"
done
cp remote/janus/janus.plugin.textroom.jcfg generated/janus/
chmod 600 generated/janus/*
./scripts/build-web-admin.sh >/dev/null
htpasswd -bcB /etc/nginx/remote-support.htpasswd "$REMOTE_ADMIN_USER" "$REMOTE_ADMIN_PASS" 2>/dev/null
chown root:www-data /etc/nginx/remote-support.htpasswd && chmod 640 /etc/nginx/remote-support.htpasswd
# nginx (www-data) must read the console; it has no secrets besides settings.js,
# which basic auth protects.
chmod 755 "$INSTALL_DIR" generated
chmod -R a+rX generated/web-admin

for site in mdm remote; do
  envsubst "$VARS" < "nginx/$site.conf.tmpl" > "/etc/nginx/sites-available/remote-support-$site.conf"
  ln -sf "/etc/nginx/sites-available/remote-support-$site.conf" /etc/nginx/sites-enabled/
done
nginx -t -q || die "nginx config test failed (nothing reloaded)"
systemctl reload nginx

# ---------------------------------------------------------------- start
log "Starting containers (first start downloads ~1 GB and takes a few minutes)"
docker compose pull -q
docker compose up -d

log "Waiting for Headwind MDM"
for i in $(seq 1 60); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "https://$MDM_DOMAIN/" || true)"
  [[ "$code" =~ ^(200|302)$ ]] && break
  sleep 5
done
[[ "${code:-}" =~ ^(200|302)$ ]] || echo "MDM not answering yet; check: docker compose logs hmdm"

# Unattended security updates for the OS.
dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null 2>&1 || true

cat <<EOF

=====================================================================
 Headwind MDM:     https://$MDM_DOMAIN
                   first login: admin / admin  -> CHANGE IT IMMEDIATELY
 Remote console:   https://$REMOTE_DOMAIN   (user: $REMOTE_ADMIN_USER, password in .env)
 Remote agent app: Server URL https://$REMOTE_DOMAIN
                   Secret     (JANUS_API_SECRET in .env)
 Secrets are stored only in $INSTALL_DIR/.env (root-only). Back it up safely.
=====================================================================
EOF
