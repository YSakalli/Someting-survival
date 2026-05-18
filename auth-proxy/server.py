#!/usr/bin/env python3
"""42-gamejam OAuth proxy for the Godot HTML5 build.

The browser cannot run the OAuth code flow directly (no TCP listen, CORS blocks
the token endpoint, and shipping client_secret in the .pck is unsafe). This
server runs locally and:

  GET /login            -> 302 to 42 authorize URL.
  GET /callback?code=.. -> server-side token exchange + /v2/me + coalitions,
                           stores result behind a random session token,
                           302s back to the game with ?session=<token>.
  GET /api/me?session=. -> returns the cached user_data as JSON with CORS,
                           then deletes the session (one-shot).

Run from repo root:
    python auth-proxy/server.py
"""
from __future__ import annotations

import configparser
import json
import secrets
import sys
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent
SECRETS_PATH = REPO_ROOT / "42api" / "secrets.cfg"

GAME_ORIGIN = "http://localhost:8000"
BACKEND_HOST = "localhost"
BACKEND_PORT = 8765
REDIRECT_URI = f"http://{BACKEND_HOST}:{BACKEND_PORT}/callback"

AUTH_URL = "https://api.intra.42.fr/oauth/authorize"
TOKEN_URL = "https://api.intra.42.fr/oauth/token"
ME_URL = "https://api.intra.42.fr/v2/me"
COALITIONS_URL = "https://api.intra.42.fr/v2/users/{uid}/coalitions"

COALITION_TO_ELEMENT = {
    "aqualis": "water",
    "terranos": "wood",
    "aerys": "air",
    "ignatus": "fire",
}

# api.intra.42.fr sits behind Cloudflare, which rejects the default
# `Python-urllib/x.y` UA with HTTP 1010. Send a normal browser UA.
USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36"
)


def load_secrets() -> tuple[str, str]:
    cfg = configparser.ConfigParser()
    cfg.read(SECRETS_PATH, encoding="utf-8")
    uid = cfg.get("api42", "uid").strip().strip('"')
    secret = cfg.get("api42", "secret").strip().strip('"')
    if not uid or not secret:
        raise SystemExit(f"UID/SECRET missing in {SECRETS_PATH}")
    return uid, secret


CLIENT_ID, CLIENT_SECRET = load_secrets()

_states: set[str] = set()
_sessions: dict[str, dict[str, Any]] = {}


def coalition_to_element(name: str, slug: str) -> str:
    key = (name + " " + slug).lower()
    for k, v in COALITION_TO_ELEMENT.items():
        if k in key:
            return v
    return "fire"


def post_form(url: str, fields: dict[str, str]) -> dict[str, Any]:
    data = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    req.add_header("Accept", "application/json")
    req.add_header("User-Agent", USER_AGENT)
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


def get_json(url: str, token: str) -> Any:
    req = urllib.request.Request(url, method="GET")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/json")
    req.add_header("User-Agent", USER_AGENT)
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


class Handler(BaseHTTPRequestHandler):
    def _cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", GAME_ORIGIN)
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def _redirect(self, location: str) -> None:
        self.send_response(302)
        self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _json(self, status: int, payload: Any) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _html(self, status: int, html: str) -> None:
        body = html.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self._cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        params = dict(urllib.parse.parse_qsl(parsed.query))

        if path == "/login":
            state = secrets.token_urlsafe(24)
            _states.add(state)
            query = urllib.parse.urlencode({
                "client_id": CLIENT_ID,
                "redirect_uri": REDIRECT_URI,
                "response_type": "code",
                "scope": "public",
                "state": state,
            })
            self._redirect(f"{AUTH_URL}?{query}")
            return

        if path == "/callback":
            err = params.get("error")
            if err:
                self._html(400, f"<h1>42 reddetti</h1><p>{err}</p>")
                return
            code = params.get("code", "")
            state = params.get("state", "")
            if not code or state not in _states:
                self._html(400, "<h1>Invalid callback (code/state)</h1>")
                return
            _states.discard(state)
            try:
                tok = post_form(TOKEN_URL, {
                    "grant_type": "authorization_code",
                    "client_id": CLIENT_ID,
                    "client_secret": CLIENT_SECRET,
                    "code": code,
                    "redirect_uri": REDIRECT_URI,
                })
                access_token = tok["access_token"]
                me = get_json(ME_URL, access_token)
                try:
                    coalitions = get_json(
                        COALITIONS_URL.format(uid=me["id"]), access_token
                    )
                except Exception:
                    coalitions = []
                if isinstance(coalitions, list) and coalitions:
                    first = coalitions[0]
                    name = first.get("name", "") or ""
                    slug = first.get("slug", "") or ""
                    me["coalition"] = name
                    me["element"] = coalition_to_element(name, slug)
                else:
                    me["coalition"] = ""
                    me["element"] = "fire"
            except urllib.error.HTTPError as ex:
                body_text = ex.read().decode("utf-8", "replace")
                self._html(
                    500,
                    f"<h1>OAuth hatasi</h1><pre>{ex.code} {ex.reason}\n{body_text}</pre>",
                )
                return
            except Exception as ex:
                self._html(500, f"<h1>OAuth hatasi</h1><pre>{type(ex).__name__}: {ex}</pre>")
                return

            session = secrets.token_urlsafe(24)
            _sessions[session] = me
            self._redirect(f"{GAME_ORIGIN}/?session={session}")
            return

        if path == "/api/me":
            session = params.get("session", "")
            data = _sessions.pop(session, None)
            if not data:
                self._json(401, {"error": "invalid or expired session"})
                return
            self._json(200, data)
            return

        self._html(404, "<h1>Not found</h1>")

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("[auth-proxy] " + (fmt % args) + "\n")


def main() -> None:
    srv = HTTPServer((BACKEND_HOST, BACKEND_PORT), Handler)
    print(f"[auth-proxy] http://{BACKEND_HOST}:{BACKEND_PORT}")
    print(f"[auth-proxy] redirect_uri = {REDIRECT_URI}")
    print(f"[auth-proxy] game origin   = {GAME_ORIGIN}")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
