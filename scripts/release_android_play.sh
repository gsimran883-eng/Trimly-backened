#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_PROPS="$ROOT_DIR/android/key.properties"
PREFLIGHT_SCRIPT="$ROOT_DIR/scripts/check_android_signing_env.sh"
KEYTOOL_BIN="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"

read_prop() {
  local key="$1"
  if [[ -f "$KEY_PROPS" ]]; then
    awk -F= -v k="$key" '$1==k {print $2}' "$KEY_PROPS" | tail -n 1
  fi
}

resolve_store_file_abs() {
  local store_file="$1"
  local dir_path
  if [[ "$store_file" = /* ]]; then
    printf '%s\n' "$store_file"
    return 0
  fi

  dir_path="$(cd "$ROOT_DIR/android/app" && cd "$(dirname "$store_file")" && pwd)"
  printf '%s/%s\n' "$dir_path" "$(basename "$store_file")"
}

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter command not found in PATH" >&2
  exit 1
fi

if [[ ! -x "$PREFLIGHT_SCRIPT" ]]; then
  echo "Missing preflight script: $PREFLIGHT_SCRIPT" >&2
  exit 1
fi

export ANDROID_KEY_ALIAS="${ANDROID_KEY_ALIAS:-$(read_prop keyAlias)}"
export ANDROID_STORE_FILE="${ANDROID_STORE_FILE:-$(read_prop storeFile)}"

STORE_FILE_ABS="$(resolve_store_file_abs "$ANDROID_STORE_FILE")"
attempt=1
while true; do
  if [[ -z "${ANDROID_STORE_PASSWORD:-}" ]]; then
    read -r -s -p "Enter ANDROID_STORE_PASSWORD: " ANDROID_STORE_PASSWORD
    echo
    export ANDROID_STORE_PASSWORD
  fi

  if "$KEYTOOL_BIN" -list -keystore "$STORE_FILE_ABS" -storepass "$ANDROID_STORE_PASSWORD" >/dev/null 2>&1; then
    break
  fi

  if (( attempt >= 3 )); then
    echo "Invalid ANDROID_STORE_PASSWORD for keystore: $STORE_FILE_ABS" >&2
    exit 1
  fi

  echo "Password did not unlock keystore. Try again." >&2
  unset ANDROID_STORE_PASSWORD
  attempt=$((attempt + 1))
done

if [[ -z "${ANDROID_KEY_PASSWORD:-}" ]]; then
  # PKCS12 keystores typically use the same password for store and key entry.
  ANDROID_KEY_PASSWORD="$ANDROID_STORE_PASSWORD"
  export ANDROID_KEY_PASSWORD
fi

echo "Keystore password verified."

"$PREFLIGHT_SCRIPT"

cd "$ROOT_DIR"
flutter build appbundle --release

echo
echo "Play bundle ready: build/app/outputs/bundle/release/app-release.aab"
