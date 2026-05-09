#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/questboard}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.ghcr.yml}"
GHCR_NAMESPACE="${GHCR_NAMESPACE:-mhdomivat-hub}"
GHCR_IMAGE_TAG="${GHCR_IMAGE_TAG:-latest}"
GHCR_USERNAME="${GHCR_USERNAME:-$GHCR_NAMESPACE}"
GHCR_TOKEN="${GHCR_TOKEN:-}"

cd "$APP_DIR"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Compose file not found: $APP_DIR/$COMPOSE_FILE"
  exit 1
fi

if [[ -n "$GHCR_TOKEN" ]]; then
  echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USERNAME" --password-stdin
else
  echo "GHCR_TOKEN not set. Assuming docker login ghcr.io was already done on this server."
fi

export GHCR_NAMESPACE
export GHCR_IMAGE_TAG

echo "Deploying QuestBoard from GHCR"
echo "  Namespace: $GHCR_NAMESPACE"
echo "  Tag:       $GHCR_IMAGE_TAG"

docker compose -f "$COMPOSE_FILE" pull
docker compose -f "$COMPOSE_FILE" up -d
docker compose -f "$COMPOSE_FILE" ps
