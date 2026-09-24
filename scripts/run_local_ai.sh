#!/bin/zsh
set -euo pipefail

AI_HOME="$HOME/Library/Application Support/ClipSnapAI"
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
PORT="${CLIPSNAP_AI_PORT:-7861}"

if [[ ! -x "$AI_HOME/bin/sd-cli" ]]; then
  echo "ClipSnap AI runtime is missing from $AI_HOME/bin" >&2
  exit 1
fi

if [[ ! -f "$AI_HOME/models/realistic-vision-v6-inpaint-q8.gguf" ]]; then
  echo "ClipSnap photorealistic model is not installed yet." >&2
  exit 1
fi

if [[ ! -f "$AI_HOME/models/sd15-vae-fp16.safetensors" ]]; then
  echo "ClipSnap VAE model is missing." >&2
  exit 1
fi

"$ADB" reverse "tcp:$PORT" "tcp:$PORT"
export CLIPSNAP_AI_PORT="$PORT"
exec python3 "${0:A:h}/local_ai_server.py"
