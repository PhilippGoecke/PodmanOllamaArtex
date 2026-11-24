#!/usr/bin/env bash
set -euo pipefail

IMAGE="${ARTEX_IMAGE:-ghcr.io/baarai/artex:latest}"
CONTAINER_NAME="${ARTEX_CONTAINER_NAME:-artex}"
PORT="${ARTEX_PORT:-8787}"
DATA_DIR="${ARTEX_DATA_DIR:-$PWD/data}"
SKILLS_DIR="${ARTEX_SKILLS_DIR:-$PWD/skills}"
OLLAMA_HOST_URL="${OLLAMA_HOST:-http://host.containers.internal:11434}"
MODEL="${ARTEX_MODEL:-inkling-2-mini:26b-a5b}"

if ! command -v podman >/dev/null 2>&1; then
  echo "podman is not installed" >&2
  exit 1
fi

mkdir -p "$DATA_DIR" "$SKILLS_DIR"

# Remove any previous container with the same name
podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

podman run -d \
  --name "$CONTAINER_NAME" \
  --add-host=host.containers.internal:host-gateway \
  -e OLLAMA_HOST="$OLLAMA_HOST_URL" \
  -e OLLAMA_BASE_URL="$OLLAMA_HOST_URL" \
  -e OLLAMA_MODEL="$MODEL" \
  -e ARTEX_MODEL="$MODEL" \
  -p "${PORT}:8080" \
  -v "${DATA_DIR}:/data:Z" \
  -v "${SKILLS_DIR}:/skills:ro,Z" \
  "$IMAGE" "$@"

echo "artex is running as '$CONTAINER_NAME' on port $PORT"
echo "Model: $MODEL"
echo "Skills mounted from: $SKILLS_DIR"
echo "Logs: podman logs -f $CONTAINER_NAME"
