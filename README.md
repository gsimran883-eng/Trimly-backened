# Trimly

A clean Flutter starter project with a polished sample screen and GitHub Actions CI.

## What's New in ClipSnap 1.4.0

- CapCut-style template recipes combining color grading, textured overlays, and stylized filters.
- New 80s Retro VHS template with warm vintage tones, cassette grain, and tracking lines.
- Enhanced Cyberpunk Tokyo style with sharper neon contrast, vivid color balance, and futuristic HUD overlays.
- Streamlined preview canvas and aspect-ratio scaling for cleaner edits and exports.
- Improved FFmpeg rendering performance, export stability, and premium-style ad unlocking.

## Run locally

```bash
cd /Users/arshaulakh/my_app
flutter pub get
flutter run
```

## Local Rambo image generation

The debug app can use a local Stable Diffusion inpainting service instead of an
API key. Connect the Android phone over USB, then start the private loopback
service and ADB tunnel:

```bash
./scripts/run_local_ai.sh
```

Keep that command running while using **Rambo Action**. The phone creates a
face-preservation mask with ML Kit; the Mac regenerates clothing, body, and the
environment with the local Realistic Vision inpainting model. The service binds
to `127.0.0.1` and is reachable from the phone only through `adb reverse`.

The runtime and model files live under
`~/Library/Application Support/ClipSnapAI/` and are not stored in this
repository or on the external drive.

## CI

This repository includes a GitHub Actions workflow at `.github/workflows/flutter.yml` that runs:

- `flutter pub get`
- `flutter analyze`
- `flutter test`

## Android Play Store release

1. Ensure local signing files exist:
	- `android/upload-keystore-play.jks`
	- `android/key.properties` (copy from `android/key.properties.example`)
2. Export signing secrets for the current shell:

```bash
export ANDROID_KEY_ALIAS=upload
export ANDROID_STORE_FILE=../upload-keystore-play.jks
export ANDROID_KEY_PASSWORD="<your-key-password>"
export ANDROID_STORE_PASSWORD="<your-store-password>"
```

3. Build the upload bundle:

```bash
flutter build appbundle --release
```

4. Upload `build/app/outputs/bundle/release/app-release.aab` to Google Play Console.

### Safer release helpers

- Preflight signing check:

```bash
./scripts/check_android_signing_env.sh
```

- One-command release build (prompts for hidden passwords if env vars are missing):

```bash
./scripts/release_android_play.sh
```
