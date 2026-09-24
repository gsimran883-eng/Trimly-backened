import base64
import os
from typing import Annotated

import httpx
from fastapi import FastAPI, File, Header, HTTPException, UploadFile
from fastapi.responses import Response

app = FastAPI(title="ClipSnap Rambo API")

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
OPENAI_ENDPOINT = os.environ.get(
    "OPENAI_IMAGE_EDIT_ENDPOINT", "https://api.openai.com/v1/images/edits"
)
OPENAI_MODEL = os.environ.get("OPENAI_IMAGE_MODEL", "gpt-image-1.5")
INTERNAL_TOKEN = os.environ.get("RAMBO_INTERNAL_TOKEN", "")

PROMPT = (
    "Transform the uploaded person into a photorealistic premium jungle "
    "commando movie portrait. Preserve the uploaded person's exact face, "
    "facial structure, skin tone, eyes, expression, facial hair, hairstyle, "
    "and head position. Regenerate everything below the jawline as an "
    "athletic action hero in a weathered black tactical tank top, dark "
    "headband, utility harness, and arm wraps. Place a fictional cinematic "
    "machine-gun prop naturally across both hands with correct anatomy. "
    "Replace the background with a dense rain-soaked tropical jungle battle "
    "scene with teal foliage, mist, rainfall, smoke, embers, warm fire, and "
    "dramatic teal-and-orange lighting. Vertical cinematic poster composition. "
    "No text, logo, watermark, duplicate person, extra fingers, extra limbs, "
    "deformed weapon, plastic skin, or face change."
)


@app.get("/health")
def health() -> dict[str, bool]:
    return {"ready": bool(OPENAI_API_KEY)}


@app.post("/v1/rambo")
async def generate_rambo(
    image: Annotated[UploadFile, File()],
    mask: Annotated[UploadFile | None, File()] = None,
    x_clipsnap_token: str | None = Header(default=None),
) -> Response:
    if INTERNAL_TOKEN and x_clipsnap_token != INTERNAL_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid client token")
    if not OPENAI_API_KEY:
        raise HTTPException(status_code=503, detail="AI backend is not configured")

    image_bytes = await image.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="Image is empty")

    files: list[tuple[str, tuple[str, bytes, str]]] = [
        ("image", (image.filename or "portrait.png", image_bytes, image.content_type or "image/png"))
    ]
    if mask is not None:
        mask_bytes = await mask.read()
        if mask_bytes:
            files.append(("mask", ("mask.png", mask_bytes, "image/png")))

    data = {
        "model": OPENAI_MODEL,
        "prompt": PROMPT,
        "size": "1024x1536",
        "quality": "high",
        "input_fidelity": "high",
    }

    try:
        async with httpx.AsyncClient(timeout=240) as client:
            upstream = await client.post(
                OPENAI_ENDPOINT,
                headers={"Authorization": f"Bearer {OPENAI_API_KEY}"},
                data=data,
                files=files,
            )
    except httpx.HTTPError as error:
        raise HTTPException(status_code=502, detail=f"AI provider unavailable: {error}") from error

    if upstream.status_code < 200 or upstream.status_code >= 300:
        detail = upstream.text[:1000]
        raise HTTPException(status_code=502, detail=f"AI provider failed: {detail}")

    try:
        payload = upstream.json()
        encoded = payload["data"][0]["b64_json"]
        output = base64.b64decode(encoded)
    except (KeyError, IndexError, TypeError, ValueError) as error:
        raise HTTPException(status_code=502, detail="AI provider returned no image") from error

    return Response(content=output, media_type="image/png")
