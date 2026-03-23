#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path


def emit_response(payload: dict) -> None:
    print(json.dumps(payload), flush=True)


def parse_json_line(raw: str) -> dict:
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"invalid json payload: {exc}") from exc


def load_backend(model_id: str, device: str, enable_thinking: bool):
    try:
        import torch
        from PIL import Image
        from transformers import AutoModel
    except Exception as exc:
        raise RuntimeError(f"missing python dependencies: {exc}") from exc

    resolved_device = device
    if resolved_device == "auto":
        if torch.cuda.is_available():
            resolved_device = "cuda"
        elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            resolved_device = "mps"
        else:
            resolved_device = "cpu"

    dtype = torch.bfloat16 if resolved_device in ("cuda", "mps") else torch.float32

    model = AutoModel.from_pretrained(
        model_id,
        trust_remote_code=True,
        torch_dtype=dtype,
        attn_implementation="sdpa",
        init_vision=True,
        init_audio=False,
        init_tts=False,
    )
    model.eval()
    if hasattr(model, "to"):
        model = model.to(resolved_device)

    def run(image_path: str, prompt: str) -> str:
        image = Image.open(image_path).convert("RGB")
        msgs = [{"role": "user", "content": [image, prompt]}]
        try:
            return model.chat(
                msgs=msgs,
                sampling=False,
                enable_thinking=enable_thinking,
                use_tts_template=False,
            )
        except TypeError:
            return model.chat(msgs=msgs)

    return run, resolved_device


def extract_json_block(raw_text: str) -> dict:
    cleaned = raw_text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.strip("`")
        if cleaned.startswith("json"):
            cleaned = cleaned[4:].strip()

    start = cleaned.find("{")
    end = cleaned.rfind("}")
    if start == -1 or end == -1 or end < start:
        return {}

    try:
        return json.loads(cleaned[start : end + 1])
    except json.JSONDecodeError:
        return {}


def build_prompt(payload: dict) -> str:
    schema_fields = payload.get("schema_fields", [])
    prompt = payload.get("prompt", "").strip()
    page_kind = payload.get("page_kind", "unknown")
    platform = payload.get("platform", "unknown")

    field_lines = []
    for field in schema_fields:
        name = field.get("name", "unknown")
        description = field.get("description", "")
        required = field.get("required", False)
        required_text = "required" if required else "optional"
        field_lines.append(f'- "{name}" ({required_text}): {description}')

    instruction = [
        "You are extracting structured GUI data from a single keyframe.",
        f"Platform: {platform}.",
        f"Page kind: {page_kind}.",
        prompt,
        "Return one strict JSON object and nothing else.",
        "If a field is unavailable, use null.",
        "Schema fields:",
        *field_lines,
    ]
    return "\n".join(instruction)


def handle_payload(payload: dict, backend_cache: dict) -> dict:
    image_path = payload.get("image_path")
    if not image_path:
        raise RuntimeError("image_path is required")

    resolved_image = Path(image_path)
    if not resolved_image.exists():
        raise RuntimeError(f"image not found: {resolved_image}")

    model_id = payload.get("model_id") or os.environ.get("MIND_MINICPM_MODEL_ID") or "openbmb/MiniCPM-o-4_5"
    device = payload.get("device") or os.environ.get("MIND_MINICPM_DEVICE") or "auto"
    enable_thinking = bool(payload.get("enable_thinking", False))
    signature = (model_id, device, enable_thinking)

    if backend_cache.get("signature") != signature:
        runner, resolved_device = load_backend(
            model_id=model_id,
            device=device,
            enable_thinking=enable_thinking,
        )
        backend_cache["signature"] = signature
        backend_cache["runner"] = runner
        backend_cache["resolved_device"] = resolved_device
        backend_cache["model_id"] = model_id

    prompt = build_prompt(payload)
    raw_text = backend_cache["runner"](str(resolved_image), prompt)
    parsed = extract_json_block(raw_text)

    return {
        "ok": True,
        "model_id": backend_cache["model_id"],
        "device": backend_cache["resolved_device"],
        "raw_text": raw_text,
        "fields": parsed,
    }


def main() -> None:
    backend_cache: dict = {}
    saw_payload = False

    for raw_line in sys.stdin:
        if not raw_line.strip():
            continue
        saw_payload = True
        try:
            payload = parse_json_line(raw_line)
            emit_response(handle_payload(payload, backend_cache))
        except Exception as exc:
            emit_response({"ok": False, "error": str(exc)})

    if not saw_payload:
        emit_response({"ok": False, "error": "stdin payload is empty"})


if __name__ == "__main__":
    main()
