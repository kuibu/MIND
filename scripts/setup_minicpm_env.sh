#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${1:-$ROOT_DIR/.venv/minicpm}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

echo "Creating MiniCPM runtime at: $VENV_DIR"
"$PYTHON_BIN" -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

python -m pip install --upgrade pip setuptools wheel
python -m pip install \
  torch \
  torchvision \
  transformers \
  pillow \
  accelerate \
  sentencepiece

cat <<EOF

MiniCPM bridge environment is ready.

Export this before launching MIND:
  export MIND_MINICPM_PYTHON="$VENV_DIR/bin/python"

Optional overrides:
  export MIND_MINICPM_MODEL_ID="openbmb/MiniCPM-o-4_5"
  export MIND_MINICPM_DEVICE="auto"

EOF
