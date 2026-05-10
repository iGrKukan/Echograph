#!/usr/bin/env python3
"""Voicekeep analyzer HTTP server.

POST /analyze with Bearer token + JSON body → runs `voicekeep_analyze.sh`,
returns the resulting Markdown.

Health check: GET /health → 'ok'.

Required env vars:
    VOICEKEEP_TOKEN   — bearer token (any non-empty string).
    VOICEKEEP_PORT    — listen port (default 8765).
"""

import json
import os
import subprocess
import sys
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

CLI_DIR = Path(__file__).resolve().parent
ANALYZER = CLI_DIR / "voicekeep_analyze.sh"

TOKEN = os.environ.get("VOICEKEEP_TOKEN")
PORT = int(os.environ.get("VOICEKEEP_PORT", "19847"))

if not TOKEN:
    print("FATAL: VOICEKEEP_TOKEN env var not set", file=sys.stderr)
    sys.exit(1)
if not ANALYZER.is_file():
    print(f"FATAL: analyzer script missing: {ANALYZER}", file=sys.stderr)
    sys.exit(1)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write(f"[{self.address_string()}] {fmt % args}\n")
        sys.stderr.flush()

    def _reject(self, code, msg):
        body = (msg + "\n").encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            body = b"ok\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self._reject(404, "not found")

    def do_POST(self):
        if self.path != "/analyze":
            return self._reject(404, "not found")

        auth = self.headers.get("Authorization", "")
        if auth != f"Bearer {TOKEN}":
            return self._reject(401, "unauthorized")

        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 10_000_000:
            return self._reject(400, "bad content length")

        body = self.rfile.read(length)
        try:
            doc = json.loads(body)
            if doc.get("version") != 1 or "transcript" not in doc:
                raise ValueError("expected version=1 and transcript field")
        except Exception as e:
            return self._reject(400, f"bad JSON: {e}")

        with tempfile.NamedTemporaryFile(
            mode="wb", suffix=".voicekeep.json", delete=False
        ) as src:
            src.write(body)
            src_path = src.name
        out_path = src_path[: -len(".voicekeep.json")] + ".analysis.md"

        try:
            res = subprocess.run(
                [str(ANALYZER), src_path, out_path],
                capture_output=True, text=True, timeout=180,
            )
            if res.returncode != 0:
                return self._reject(
                    502,
                    f"analyzer failed (rc={res.returncode}): {res.stderr.strip()}",
                )
            md = Path(out_path).read_text(encoding="utf-8")
            data = md.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/markdown; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except subprocess.TimeoutExpired:
            self._reject(504, "analyzer timed out")
        finally:
            for p in (src_path, out_path):
                try:
                    os.unlink(p)
                except FileNotFoundError:
                    pass


def main():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"voicekeep server listening on 0.0.0.0:{PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
