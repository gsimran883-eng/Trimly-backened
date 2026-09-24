#!/usr/bin/env python3
import cgi
import json
import os
import subprocess
import tempfile
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

HOST = "127.0.0.1"
PORT = int(os.environ.get("CLIPSNAP_AI_PORT", "7861"))
AI_HOME = Path.home() / "Library" / "Application Support" / "ClipSnapAI"
CLI = AI_HOME / "bin" / "sd-cli"
MODEL = AI_HOME / "models" / "realistic-vision-v6-inpaint-q8.gguf"
VAE = AI_HOME / "models" / "sd15-vae-fp16.safetensors"
MAX_UPLOAD_BYTES = 30 * 1024 * 1024
PROMPT = (
    "photorealistic cinematic jungle commando portrait, same person and face, "
    "athletic action hero body, weathered black tactical tank top, dark headband, "
    "utility harness, holding a fictional heavy machine gun prop, dense tropical "
    "jungle, rainfall, teal mist, smoke, orange fire and embers, dramatic rim "
    "lighting, realistic skin, detailed fabric and metal, premium movie poster"
)
NEGATIVE_PROMPT = (
    "different face, celebrity, duplicate person, extra limbs, extra fingers, "
    "deformed hands, deformed weapon, cartoon, illustration, plastic skin, blurry, "
    "low quality, text, logo, watermark"
)


class Handler(BaseHTTPRequestHandler):
    server_version = "ClipSnapLocalAI/1.0"

    def do_GET(self):
        if self.path != "/health":
            self.send_error(404)
            return
        ready = all(path.is_file() for path in (CLI, MODEL, VAE))
        body = json.dumps({"ready": ready, "engine": "sd1.5-inpaint-q8"}).encode()
        self.send_response(200 if ready else 503)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/v1/rambo":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > MAX_UPLOAD_BYTES:
            self.send_error(413, "Upload must be between 1 byte and 30 MB")
            return
        if not all(path.is_file() for path in (CLI, MODEL, VAE)):
            self.send_error(503, "Local AI model is not installed")
            return

        form = cgi.FieldStorage(
            fp=self.rfile,
            headers=self.headers,
            environ={
                "REQUEST_METHOD": "POST",
                "CONTENT_TYPE": self.headers.get("Content-Type", ""),
                "CONTENT_LENGTH": str(length),
            },
        )
        if "image" not in form or "mask" not in form:
            self.send_error(400, "image and mask files are required")
            return

        image_bytes = form["image"].file.read()
        mask_bytes = form["mask"].file.read()
        if not image_bytes or not mask_bytes:
            self.send_error(400, "image and mask files cannot be empty")
            return

        with tempfile.TemporaryDirectory(prefix="clipsnap-ai-") as temp_dir:
            temp = Path(temp_dir)
            image_path = temp / "source.jpg"
            mask_path = temp / "mask.png"
            output_path = temp / "result.png"
            image_path.write_bytes(image_bytes)
            mask_path.write_bytes(mask_bytes)

            command = [
                str(CLI),
                "-m", str(MODEL),
                "--vae", str(VAE),
                "--backend", "cpu",
                "--init-img", str(image_path),
                "--mask", str(mask_path),
                "--strength", "0.88",
                "--prompt", PROMPT,
                "--negative-prompt", NEGATIVE_PROMPT,
                "--width", "384",
                "--height", "576",
                "--steps", "10",
                "--cfg-scale", "7",
                "--sampling-method", "euler_a",
                "--vae-tiling",
                "--mmap",
                "--output", str(output_path),
            ]
            environment = os.environ.copy()
            environment["DYLD_LIBRARY_PATH"] = str(CLI.parent)
            try:
                completed = subprocess.run(
                    command,
                    env=environment,
                    capture_output=True,
                    text=True,
                    timeout=900,
                )
            except subprocess.TimeoutExpired:
                self.send_error(504, "Local generation timed out")
                return

            if completed.returncode != 0 or not output_path.is_file():
                message = (completed.stderr or completed.stdout)[-1200:]
                self.send_error(500, "Local generation failed: " + message)
                return

            upscale = subprocess.run(
                ["/usr/bin/sips", "-z", "1536", "1024", str(output_path)],
                capture_output=True,
                text=True,
            )
            if upscale.returncode != 0:
                self.send_error(500, "Failed to prepare HD output")
                return

            result = output_path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(result)))
            self.end_headers()
            self.wfile.write(result)

    def log_message(self, format_string, *args):
        print("[ClipSnapAI] " + format_string % args, flush=True)


if __name__ == "__main__":
    server = HTTPServer((HOST, PORT), Handler)
    print(f"ClipSnap local AI listening on http://{HOST}:{PORT}", flush=True)
    server.serve_forever()
