#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${ARTEX_REPO_URL:-https://github.com/PhilippGoecke/ARTEX.git}"
SRC_DIR="${ARTEX_SRC_DIR:-$PWD/ARTEX}"
IMAGE="${ARTEX_IMAGE:-ghcr.io/baarai/artex:latest}"
CONTAINER_NAME="${ARTEX_CONTAINER_NAME:-artex}"
PORT="${ARTEX_PORT:-8787}"
DATA_DIR="${ARTEX_DATA_DIR:-$PWD/data}"
SKILLS_DIR="${ARTEX_SKILLS_DIR:-$PWD/skills}"
OLLAMA_HOST_URL="${OLLAMA_HOST:-http://host.containers.internal:11434}"
MODEL="${ARTEX_MODEL:-inkling-2-mini:26b-a5b}"
NETWORK="${ARTEX_NETWORK:-artex-net}"
PG_CONTAINER="${ARTEX_PG_CONTAINER:-artex-postgres}"
PG_IMAGE="${ARTEX_PG_IMAGE:-docker.io/library/postgres:16}"
PG_VOLUME="${ARTEX_PG_VOLUME:-artex-pgdata}"
PG_USER="${POSTGRES_USER:-artex}"
PG_DB="${POSTGRES_DB:-artex}"

if ! command -v podman >/dev/null 2>&1; then
  echo "podman is not installed" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is not installed" >&2
  exit 1
fi

# Clone or update the repository
if [ -d "$SRC_DIR/.git" ]; then
  git -C "$SRC_DIR" pull --ff-only
else
  git clone "$REPO_URL" "$SRC_DIR"
fi

# Create .env from the example if missing
if [ ! -f "$SRC_DIR/.env" ]; then
  cp "$SRC_DIR/.env.example" "$SRC_DIR/.env"
  echo "Created $SRC_DIR/.env - set POSTGRES_PASSWORD (and optionally ANTHROPIC_API_KEY) before running." >&2
fi

# Load .env (POSTGRES_PASSWORD etc.)
set -a
# shellcheck disable=SC1091
. "$SRC_DIR/.env"
set +a

: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD must be set in $SRC_DIR/.env}"

# Build the image
podman build -t "$IMAGE" "$SRC_DIR"

mkdir -p "$DATA_DIR" "$SKILLS_DIR"

# Network and volume
podman network exists "$NETWORK" || podman network create "$NETWORK"
podman volume exists "$PG_VOLUME" || podman volume create "$PG_VOLUME"

# Remove previous containers
podman rm -f "$CONTAINER_NAME" "$PG_CONTAINER" >/dev/null 2>&1 || true

# Start Postgres
podman run -d \
  --name "$PG_CONTAINER" \
  --network "$NETWORK" \
  -e POSTGRES_USER="$PG_USER" \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -e POSTGRES_DB="$PG_DB" \
  -v "${PG_VOLUME}:/var/lib/postgresql/data:Z" \
  "$PG_IMAGE"

# Wait until Postgres is ready
echo "Waiting for Postgres..."
for _ in $(seq 1 30); do
  if podman exec "$PG_CONTAINER" pg_isready -U "$PG_USER" -d "$PG_DB" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
podman exec "$PG_CONTAINER" pg_isready -U "$PG_USER" -d "$PG_DB" >/dev/null

# Start artex
podman run -d \
  --name "$CONTAINER_NAME" \
  --network "$NETWORK" \
  --add-host=host.containers.internal:host-gateway \
  --env-file "$SRC_DIR/.env" \
  -e DATABASE_URL="postgresql://${PG_USER}:${POSTGRES_PASSWORD}@${PG_CONTAINER}:5432/${PG_DB}" \
  -e POSTGRES_HOST="$PG_CONTAINER" \
  -e POSTGRES_USER="$PG_USER" \
  -e POSTGRES_DB="$PG_DB" \
  -e ARTEX_PG_DSN="postgresql://${PG_USER}:${POSTGRES_PASSWORD}@${PG_CONTAINER}:5432/${PG_DB}" \
  -e ARTEX_PG_HOST="$PG_CONTAINER" \
  -e ARTEX_PG_PORT="5432" \
  -e ARTEX_PG_USER="$PG_USER" \
  -e ARTEX_PG_PASSWORD="$POSTGRES_PASSWORD" \
  -e ARTEX_PG_DBNAME="$PG_DB" \
  -e OLLAMA_HOST="$OLLAMA_HOST_URL" \
  -e OLLAMA_BASE_URL="$OLLAMA_HOST_URL" \
  -e OLLAMA_MODEL="$MODEL" \
  -e ARTEX_MODEL="$MODEL" \
  -p "${PORT}:8080" \
  -v "${DATA_DIR}:/data:Z" \
  -v "${SKILLS_DIR}:/skills:ro,Z" \
  "$IMAGE" "$@"

echo "artex is running as '$CONTAINER_NAME' on port $PORT"
echo "Postgres: $PG_CONTAINER (volume: $PG_VOLUME)"
echo "Model: $MODEL"
echo "Skills mounted from: $SKILLS_DIR"
echo "Logs: podman logs -f $CONTAINER_NAME"
echo "Postgres logs: podman logs -f $PG_CONTAINER"
