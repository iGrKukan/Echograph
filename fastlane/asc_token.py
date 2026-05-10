"""Helper to mint App Store Connect API JWT tokens.

Loads key & issuer from fastlane/secrets/asc.env (gitignored).
"""
import jwt
import os
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SECRETS = ROOT / "secrets"

KEY_ID = "798ZTD68WF"
ISSUER_ID = "69a6de8e-0e6d-47e3-e053-5b8c7c11a4d1"
KEY_PATH = SECRETS / f"AuthKey_{KEY_ID}.p8"
TEAM_ID = "ZVYKY9TF2X"
BUNDLE_ID = "by.timberbid.echograph"


def make_token(ttl_seconds: int = 1200) -> str:
    private_key = KEY_PATH.read_text()
    now = int(time.time())
    payload = {
        "iss": ISSUER_ID,
        "iat": now,
        "exp": now + ttl_seconds,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(
        payload,
        private_key,
        algorithm="ES256",
        headers={"kid": KEY_ID, "typ": "JWT"},
    )


def auth_headers() -> dict:
    return {"Authorization": f"Bearer {make_token()}"}


if __name__ == "__main__":
    print(make_token())
