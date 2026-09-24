# ClipSnap Rambo backend

This service keeps `OPENAI_API_KEY` off the mobile app. It accepts the source
image and optional face-preservation mask at `POST /v1/rambo` and returns a PNG.

## Run locally

```bash
cd backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
export OPENAI_API_KEY=...
uvicorn rambo_api:app --host 0.0.0.0 --port 8080
```

Set `RAMBO_INTERNAL_TOKEN` on the server and pass the same value to the app as
`--dart-define=RAMBO_BACKEND_TOKEN=...` when the endpoint should require a
client token. Deploy the container to Cloud Run, Render, Fly.io, or another
HTTPS container host, then build the app with:

```bash
flutter build appbundle --release \
  --dart-define=RAMBO_BACKEND_ENDPOINT=https://your-host.example/v1/rambo \
  --dart-define=RAMBO_BACKEND_TOKEN=your-client-token
```

Use a server-side secret manager for `OPENAI_API_KEY`; do not put that key in
Flutter `--dart-define` values.
