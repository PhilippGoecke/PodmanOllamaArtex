#!/usr/bin/env bash
set -euo pipefail

IMAGE="${ARTEX_IMAGE:-artex:latest}"
CONTAINER_NAME="${ARTEX_CONTAINER_NAME:-artex}"
PORT="${ARTEX_PORT:-8787}"
DATA_DIR="${ARTEX_DATA_DIR:-$PWD/data}"
OLLAMA_HOST_URL="${OLLAMA_HOST:-http://host.containers.internal:11434}"

if ! command -v podman >/dev/null 2>&1; then
  echo "podman is not installed" >&2
  exit 1
fi

mkdir -p "$DATA_DIR"

# Remove any previous container with the same name
podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

podman run -d \
  --name "$CONTAINER_NAME" \
  --add-host=host.containers.internal:host-gateway \
  -e OLLAMA_HOST="$OLLAMA_HOST_URL" \
  -e OLLAMA_BASE_URL="$OLLAMA_HOST_URL" \
  -p "${PORT}:8080" \
  -v "${DATA_DIR}:/data:Z" \
  "$IMAGE" "$@"

echo "artex is running as '$CONTAINER_NAME' on port $PORT"
echo "Logs: podman logs -f $CONTAINER_NAME"
