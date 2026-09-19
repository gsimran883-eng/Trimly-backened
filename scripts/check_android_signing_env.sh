#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_PROPS="$ROOT_DIR/android/key.properties"

read_prop() {
  local key="$1"
  if [[ -f "$KEY_PROPS" ]]; then
    awk -F= -v k="$key" '$1==k {print $2}' "$KEY_PROPS" | tail -n 1
  fi
}

resolve_store_file_abs() {
  local store_file="$1"
  local dir_path
  if [[ -z "$store_file" ]]; then
    return 0
  fi

  if [[ "$store_file" = /* ]]; then
    printf '%s\n' "$store_file"
    return 0
  fi

  dir_path="$(cd "$ROOT_DIR/android/app" && cd "$(dirname "$store_file")" && pwd)"
  printf '%s/%s\n' "$dir_path" "$(basename "$store_file")"
}

KEY_ALIAS="${ANDROID_KEY_ALIAS:-$(read_prop keyAlias)}"
STORE_FILE="${ANDROID_STORE_FILE:-$(read_prop storeFile)}"
KEY_PASSWORD="${ANDROID_KEY_PASSWORD:-}"
STORE_PASSWORD="${ANDROID_STORE_PASSWORD:-}"

missing=()

if [[ -z "$KEY_ALIAS" ]]; then
  missing+=("ANDROID_KEY_ALIAS or android/key.properties keyAlias")
fi

if [[ -z "$STORE_FILE" ]]; then
  missing+=("ANDROID_STORE_FILE or android/key.properties storeFile")
fi

if [[ -z "$KEY_PASSWORD" ]]; then
  missing+=("ANDROID_KEY_PASSWORD")
fi

if [[ -z "$STORE_PASSWORD" ]]; then
  missing+=("ANDROID_STORE_PASSWORD")
fi

if (( ${#missing[@]} > 0 )); then
  printf 'Android release signing preflight failed. Missing:\n' >&2
  for item in "${missing[@]}"; do
    printf '  - %s\n' "$item" >&2
  done
  exit 1
fi

STORE_FILE_ABS="$(resolve_store_file_abs "$STORE_FILE")"
if [[ ! -f "$STORE_FILE_ABS" ]]; then
  printf 'Android release signing preflight failed. Keystore not found: %s\n' "$STORE_FILE_ABS" >&2
  exit 1
fi

printf 'Android signing preflight passed.\n'
printf '  keyAlias: %s\n' "$KEY_ALIAS"
printf '  storeFile: %s\n' "$STORE_FILE_ABS"
