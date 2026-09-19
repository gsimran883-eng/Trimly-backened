#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_PROPERTIES="$ROOT_DIR/android/local.properties"

if [[ ! -f "$LOCAL_PROPERTIES" ]]; then
  echo "Missing android/local.properties"
  exit 1
fi

SDK_DIR="$(awk -F= '/^sdk.dir=/{print $2}' "$LOCAL_PROPERTIES" | tail -n 1)"
SDK_DIR="${SDK_DIR//\\:/:}"

if [[ -z "$SDK_DIR" ]]; then
  echo "Could not read sdk.dir from android/local.properties"
  exit 1
fi

ADB_BIN="$SDK_DIR/platform-tools/adb"
EMU_BIN="$SDK_DIR/emulator/emulator"
AVD_NAME="${1:-clipsnap_android}"
APP_ID="com.clipsnap.editor"
MAIN_ACTIVITY="$APP_ID/.MainActivity"
APK_PATH="$ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk"

if [[ ! -x "$ADB_BIN" ]]; then
  echo "adb not found at $ADB_BIN"
  exit 1
fi

if [[ ! -x "$EMU_BIN" ]]; then
  echo "emulator not found at $EMU_BIN"
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter command not found in PATH"
  exit 1
fi

pick_device() {
  "$ADB_BIN" devices | awk 'NR>1 && $2=="device" && $1 ~ /^emulator-/{print $1; exit}'
}

DEVICE_ID="$(pick_device || true)"

if [[ -z "$DEVICE_ID" ]]; then
  echo "Starting emulator: $AVD_NAME"
  nohup "$EMU_BIN" \
    -avd "$AVD_NAME" \
    -gpu swiftshader_indirect \
    -no-snapshot-save \
    -memory 1536 \
    >/tmp/${AVD_NAME}_emu.log 2>&1 &

  "$ADB_BIN" wait-for-device

  echo "Waiting for Android boot completion..."
  for _ in {1..120}; do
    BOOTED="$($ADB_BIN shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    if [[ "$BOOTED" == "1" ]]; then
      break
    fi
    sleep 1
  done
fi

DEVICE_ID="$(pick_device || true)"
if [[ -z "$DEVICE_ID" ]]; then
  echo "No running emulator detected"
  exit 1
fi

echo "Using device: $DEVICE_ID"

cd "$ROOT_DIR"
flutter build apk --release

if [[ ! -f "$APK_PATH" ]]; then
  echo "Release APK not found at $APK_PATH"
  exit 1
fi

"$ADB_BIN" -s "$DEVICE_ID" install -r "$APK_PATH"
"$ADB_BIN" -s "$DEVICE_ID" shell am start -W -n "$MAIN_ACTIVITY"

echo "Verifying foreground activity..."
"$ADB_BIN" -s "$DEVICE_ID" shell dumpsys activity activities \
  | grep -E "topResumedActivity|mCurrentFocus|$APP_ID" | head -n 10

echo
echo "App launched successfully on $DEVICE_ID"
echo "Emulator log: /tmp/${AVD_NAME}_emu.log"