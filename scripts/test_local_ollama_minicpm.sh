#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "" ]; then
  echo "usage: $0 /path/to/image [prompt]" >&2
  exit 1
fi

IMAGE_PATH="$1"
PROMPT="${2:-Return one strict JSON object and nothing else. Describe the visible screen with keys title, items, and note.}"
HOST="${MIND_OLLAMA_HOST:-http://127.0.0.1:11434}"
MODEL="${MIND_OLLAMA_MODEL_ID:-openbmb/minicpm-o4.5:latest}"

python3 - "$IMAGE_PATH" "$PROMPT" "$HOST" "$MODEL" <<'PY'
import base64
import json
import sys
import urllib.request

image_path, prompt, host, model = sys.argv[1:5]

with open(image_path, "rb") as handle:
    image_base64 = base64.b64encode(handle.read()).decode("utf-8")

payload = {
    "model": model,
    "prompt": prompt,
    "images": [image_base64],
    "stream": False,
    "format": "json",
    "options": {"temperature": 0},
}

request = urllib.request.Request(
    host.rstrip("/") + "/api/generate",
    data=json.dumps(payload).encode("utf-8"),
    headers={"Content-Type": "application/json"},
)

with urllib.request.urlopen(request) as response:
    print(response.read().decode("utf-8"))
PY
