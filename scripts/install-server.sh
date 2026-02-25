#!/usr/bin/env bash
set -euo pipefail

# QuestBoard server bootstrap for fresh Debian/Ubuntu hosts (e.g. Hetzner Cloud).
# Installs Docker Engine + Compose plugin, prepares env/caddy files, then starts the stack.

APP_DIR_DEFAULT="/opt/questboard"
APP_DIR="${APP_DIR:-$APP_DIR_DEFAULT}"
DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
SKIP_START="${SKIP_START:-false}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
Usage:
  sudo bash scripts/install-server.sh

Optional environment variables:
  APP_DIR=/opt/questboard           Target directory of the project (default: /opt/questboard)
  DOMAIN=quest.example.com          If set, writes a domain-based Caddyfile
  EMAIL=admin@example.com           Optional contact email for Caddy ACME
  SKIP_START=true                   Skip docker compose up -d --build

Expected flow:
  1) Clone repo to APP_DIR (or copy files there).
  2) Run this script as root.
  3) Edit APP_DIR/.env with strong secrets.
  4) Re-run script or run docker compose up -d --build.
EOF
  exit 0
fi

if [[ "$EUID" -ne 0 ]]; then
  echo "This script must run as root. Use: sudo bash scripts/install-server.sh"
  exit 1
fi

if [[ ! -d "$APP_DIR" ]]; then
  echo "App directory does not exist: $APP_DIR"
  echo "Clone your repo first, e.g.:"
  echo "  git clone <REPO_URL> \"$APP_DIR\""
  exit 1
fi

if [[ ! -f "$APP_DIR/docker-compose.yml" ]]; then
  echo "docker-compose.yml not found in $APP_DIR"
  exit 1
fi

echo "[1/8] Installing base packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release git apt-transport-https

echo "[2/8] Installing Docker Engine + Compose plugin..."
install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi

ARCH="$(dpkg --print-architecture)"
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
if [[ -z "$CODENAME" ]]; then
  echo "Could not determine Ubuntu codename from /etc/os-release"
  exit 1
fi

cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $CODENAME stable
EOF

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl start docker

echo "[3/8] Validating Docker installation..."
docker --version
docker compose version

echo "[4/8] Preparing .env..."
cd "$APP_DIR"
if [[ ! -f ".env" ]]; then
  if [[ -f ".env.example" ]]; then
    cp .env.example .env
    echo "Created $APP_DIR/.env from .env.example"
  else
    echo "Missing .env.example. Please create .env manually."
    exit 1
  fi
fi

echo "[5/8] Preparing Caddyfile..."
if [[ -n "$DOMAIN" ]]; then
  if [[ -n "$EMAIL" ]]; then
    cat > Caddyfile <<EOF
$DOMAIN {
  tls $EMAIL
  reverse_proxy web:3000
}
EOF
  else
    cat > Caddyfile <<EOF
$DOMAIN {
  reverse_proxy web:3000
}
EOF
  fi
  echo "Wrote domain Caddyfile for: $DOMAIN"
else
  if [[ ! -f "Caddyfile" && -f "Caddyfile.example" ]]; then
    cp Caddyfile.example Caddyfile
    echo "Copied Caddyfile.example -> Caddyfile"
  fi
fi

echo "[6/8] Pulling/building images..."
docker compose -f docker-compose.yml pull || true
docker compose -f docker-compose.yml build

if [[ "$SKIP_START" == "true" ]]; then
  echo "[7/8] SKIP_START=true, not starting services."
else
  echo "[7/8] Starting services..."
  docker compose -f docker-compose.yml up -d
fi

echo "[8/8] Final status"
docker compose -f docker-compose.yml ps

cat <<EOF

Done.
Next important steps:
1) Edit $APP_DIR/.env and set strong values:
   - POSTGRES_PASSWORD
   - BOOTSTRAP_ADMIN_USERNAME
   - BOOTSTRAP_ADMIN_PASSWORD
   - APP_BASE_URL
2) If you changed .env, restart:
   docker compose -f $APP_DIR/docker-compose.yml up -d --build
3) Check logs:
   docker compose -f $APP_DIR/docker-compose.yml logs -f --tail=200
EOF

