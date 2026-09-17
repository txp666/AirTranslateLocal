#!/usr/bin/env bash
# Explicit setup only. Normal application startup calls --check, never pip/download.
set -euo pipefail

MLX_LM_VERSION="0.31.3"
RUNTIME_DIR="${AIRTRANSLATE_LOCAL_RUNTIME_DIR:-$HOME/Library/Application Support/AirTranslate/LocalMLX}"
MODEL_ID="${AIRTRANSLATE_LOCAL_MODEL:-mlx-community/Hy-MT2-7B-8bit}"
EXISTING_PYTHON="${AIRTRANSLATE_LOCAL_PYTHON:-}"
ENV_PYTHON_OVERRIDE="$EXISTING_PYTHON"
DOWNLOAD_MODEL=0
CHECK_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime-dir|--model|--python)
      [[ $# -ge 2 && -n "$2" ]] || { echo "Missing value for $1" >&2; exit 2; }
      case "$1" in
        --runtime-dir) RUNTIME_DIR="$2" ;;
        --model) MODEL_ID="$2" ;;
        --python) EXISTING_PYTHON="$2" ;;
      esac
      shift 2 ;;
    --download-model) DOWNLOAD_MODEL=1; shift ;;
    --check) CHECK_ONLY=1; shift ;;
    --help)
      echo "Usage: setup_local_mlx.sh [--runtime-dir PATH] [--python EXISTING_VENV_PYTHON] [--model MODEL_ID] [--download-model] [--check]"
      echo "Requires Python 3.11+ on Apple Silicon. --download-model explicitly downloads the selected model; --check is offline and read-only."
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

RUNTIME_PYTHON="$RUNTIME_DIR/.venv/bin/python"
if [[ -z "$EXISTING_PYTHON" ]]; then
  EXISTING_PYTHON="$RUNTIME_PYTHON"
fi

compatible_runtime() {
  [[ -x "$1" ]] || return 1
  "$1" - "$MLX_LM_VERSION" >/dev/null 2>&1 <<'PY'
import importlib.metadata
import importlib.util
import sys
from packaging.requirements import Requirement

assert sys.version_info >= (3, 11)
assert importlib.metadata.version("mlx-lm") == sys.argv[1]
# Inspect modules and dependency metadata without initializing a Metal device.
# This also detects interrupted/partial installs instead of trusting a single
# leftover mlx-lm.dist-info directory.
for module in ("mlx.core", "mlx_lm", "huggingface_hub", "transformers", "tokenizers", "safetensors"):
    assert importlib.util.find_spec(module) is not None, module
pending, seen = ["mlx-lm"], set()
while pending:
    name = pending.pop()
    if name in seen:
        continue
    seen.add(name)
    distribution = importlib.metadata.distribution(name)
    for entry in distribution.requires or []:
        requirement = Requirement(entry)
        if requirement.marker and not requirement.marker.evaluate({"extra": ""}):
            continue
        version = importlib.metadata.version(requirement.name)
        assert not requirement.specifier or requirement.specifier.contains(version, prereleases=True), entry
        pending.append(requirement.name)
PY
}

if compatible_runtime "$EXISTING_PYTHON"; then
  RUNTIME_PYTHON="$EXISTING_PYTHON"
  echo "Using installed MLX runtime: $RUNTIME_PYTHON (mlx-lm $MLX_LM_VERSION)"
elif [[ -n "$ENV_PYTHON_OVERRIDE" && "$EXISTING_PYTHON" == "$ENV_PYTHON_OVERRIDE" ]]; then
  echo "AIRTRANSLATE_LOCAL_PYTHON points to an incompatible or incomplete runtime: $EXISTING_PYTHON" >&2
  echo "Repair that environment, or unset AIRTRANSLATE_LOCAL_PYTHON and retry to prepare the standard runtime. No alternate environment was installed. / 请修复指定环境，或取消 AIRTRANSLATE_LOCAL_PYTHON 后重试。" >&2
  exit 14
elif [[ "$CHECK_ONLY" == 1 ]]; then
  echo "Local runtime is not prepared. Choose Prepare Model, or run script/setup_local_mlx.sh --download-model. / 请先准备本地模型环境。" >&2
  exit 10
else
  BOOTSTRAP_PYTHON=""
  for candidate in "${AIRTRANSLATE_BOOTSTRAP_PYTHON:-}" /opt/homebrew/bin/python3 /usr/local/bin/python3 "$(command -v python3 || true)"; do
    [[ "$candidate" != /usr/bin/python3 ]] || continue
    if [[ -n "$candidate" && -x "$candidate" ]] && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1; then
      BOOTSTRAP_PYTHON="$candidate"
      break
    fi
  done
  if [[ -z "$BOOTSTRAP_PYTHON" ]]; then
    echo "Python 3.11 or newer is required. Install Python for Apple Silicon from python.org, then retry. AirTranslate does not install Homebrew or system dependencies. / 请先安装 Python 3.11 或更新版本，再重试。" >&2
    exit 11
  fi
  if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    echo "The bundled MLX runtime requires an Apple Silicon Mac. / MLX 本地运行环境需要 Apple 芯片 Mac。" >&2
    exit 12
  fi
  mkdir -p "$RUNTIME_DIR"
  if [[ ! -x "$RUNTIME_PYTHON" ]]; then
    echo "Creating isolated Python environment: $RUNTIME_DIR/.venv"
    "$BOOTSTRAP_PYTHON" -m venv "$RUNTIME_DIR/.venv"
  elif ! "$RUNTIME_PYTHON" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1; then
    echo "Updating the managed virtual environment to Python 3.11 or newer"
    "$BOOTSTRAP_PYTHON" -m venv --upgrade "$RUNTIME_DIR/.venv"
  fi
  # A cancelled venv creation can leave Python installed before ensurepip has
  # finished. Restore its bundled pip offline before attempting dependencies.
  if ! "$RUNTIME_PYTHON" -m pip --version >/dev/null 2>&1; then
    echo "Restoring pip in the managed virtual environment"
    "$RUNTIME_PYTHON" -m ensurepip --upgrade
  fi
  echo "Installing verified runtime dependency: mlx-lm==$MLX_LM_VERSION"
  "$RUNTIME_PYTHON" -m pip --disable-pip-version-check install "mlx-lm==$MLX_LM_VERSION"
  if ! compatible_runtime "$RUNTIME_PYTHON"; then
    echo "Repairing an incomplete MLX installation"
    "$RUNTIME_PYTHON" -m pip --disable-pip-version-check install --force-reinstall "mlx-lm==$MLX_LM_VERSION"
  fi
  compatible_runtime "$RUNTIME_PYTHON" || { echo "The installed MLX runtime cannot be imported. Check the diagnostics above." >&2; exit 10; }
fi

if [[ "$CHECK_ONLY" == 1 || "$DOWNLOAD_MODEL" == 1 ]]; then
  export HF_HUB_DISABLE_XET="${HF_HUB_DISABLE_XET:-1}"
  # An explicit download opts into network; --check always stays offline.
  if [[ "$CHECK_ONLY" == 1 ]]; then
    export HF_HUB_OFFLINE=1
    export TRANSFORMERS_OFFLINE=1
  else
    export HF_HUB_OFFLINE=0
    export TRANSFORMERS_OFFLINE=0
  fi
  "$RUNTIME_PYTHON" - "$MODEL_ID" "$CHECK_ONLY" <<'PY'
import json
import pathlib
import sys
from huggingface_hub import snapshot_download

model, offline = sys.argv[1], sys.argv[2] == "1"
try:
    path = pathlib.Path(model).expanduser()
    if not path.is_dir():
        print(("Checking cached model: " if offline else "Downloading selected model: ") + model, flush=True)
        path = pathlib.Path(snapshot_download(repo_id=model, local_files_only=offline))
    if not (path / "config.json").is_file():
        raise ValueError("config.json is missing")
    index_path = path / "model.safetensors.index.json"
    if index_path.is_file():
        weights = set(json.loads(index_path.read_text())["weight_map"].values())
        if not weights or not all((path / filename).is_file() for filename in weights):
            raise ValueError("one or more model weight shards are missing")
    elif not any(path.glob("*.safetensors")):
        raise ValueError("model weights are missing")
    if not any((path / filename).is_file() for filename in ("tokenizer.json", "tokenizer.model")):
        raise ValueError("tokenizer files are missing")
    print("Model is available offline: " + str(path), flush=True)
except Exception as error:
    print("Model is not ready: " + str(error), file=sys.stderr)
    print("Choose Prepare Model, or run script/setup_local_mlx.sh --download-model. / 请显式下载所选模型后重试。", file=sys.stderr)
    raise SystemExit(13)
PY
fi

echo "Local model environment is ready. / 本地模型环境已准备好。"
