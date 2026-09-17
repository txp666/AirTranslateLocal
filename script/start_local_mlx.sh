#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCAL_MODEL_ID="${AIRTRANSLATE_LOCAL_MODEL:-mlx-community/Hy-MT2-7B-8bit}"
LOCAL_SERVER_PORT="${AIRTRANSLATE_LOCAL_PORT:-8080}"
LOCAL_RUNTIME_PYTHON="${AIRTRANSLATE_LOCAL_PYTHON:-}"

if [[ -z "$LOCAL_RUNTIME_PYTHON" ]]; then
  LOCAL_RUNTIME_DIR="${AIRTRANSLATE_LOCAL_RUNTIME_DIR:-$HOME/Library/Application Support/AirTranslate/LocalMLX}"
  LOCAL_RUNTIME_PYTHON="$LOCAL_RUNTIME_DIR/.venv/bin/python"
  if [[ ! -x "$LOCAL_RUNTIME_PYTHON" && -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
    LOCAL_RUNTIME_PYTHON="$PROJECT_ROOT/.venv/bin/python"
  fi
fi
if [[ ! -x "$LOCAL_RUNTIME_PYTHON" ]]; then
  echo "Local MLX runtime not found. Run ./script/setup_local_mlx.sh --download-model first." >&2
  exit 1
fi
case "$LOCAL_SERVER_PORT" in
  ''|*[!0-9]*) echo "AIRTRANSLATE_LOCAL_PORT must be an integer from 1024 to 65535." >&2; exit 2 ;;
esac
if (( ${#LOCAL_SERVER_PORT} > 5 )); then
  echo "AIRTRANSLATE_LOCAL_PORT must be an integer from 1024 to 65535." >&2
  exit 2
fi
LOCAL_SERVER_PORT=$((10#$LOCAL_SERVER_PORT))
if (( LOCAL_SERVER_PORT < 1024 || LOCAL_SERVER_PORT > 65535 )); then
  echo "AIRTRANSLATE_LOCAL_PORT must be an integer from 1024 to 65535." >&2
  exit 2
fi

# Downloads belong to explicit setup, never to ordinary model startup.
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
export PYTHONUNBUFFERED=1

echo "Starting cached local model: $LOCAL_MODEL_ID"
echo "API endpoint: http://127.0.0.1:$LOCAL_SERVER_PORT/v1"
exec "$LOCAL_RUNTIME_PYTHON" -m mlx_lm server \
  --model "$LOCAL_MODEL_ID" --host 127.0.0.1 --port "$LOCAL_SERVER_PORT" --log-level CRITICAL
