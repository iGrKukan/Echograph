"""Upload Review Screenshots for Pro Lifetime / Pro+ Monthly / Pro+ Yearly.

App Store Connect requires a single review screenshot per IAP / subscription
that shows where the product appears in the app. Three-step API flow:

1. POST reservation → returns uploadOperations
2. PUT raw bytes to each upload chunk
3. PATCH uploaded=true + sourceFileChecksum (md5 base64-less? actually md5 hex)

Image: marketing/screenshots/03-settings.png (1206x2622 — settings/paywall).
"""
import hashlib
import json
import sys
from pathlib import Path
import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_token import auth_headers

BASE = "https://api.appstoreconnect.apple.com"
H = {**auth_headers(), "Content-Type": "application/json"}

IMAGE = Path(__file__).resolve().parent.parent / "marketing/screenshots/03-settings.png"
assert IMAGE.exists(), IMAGE

PRO_LIFETIME = "6768049449"
PROPLUS_MONTHLY = "6768049087"
PROPLUS_YEARLY = "6768049481"


def md5_hex(path: Path) -> str:
    h = hashlib.md5()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def upload_iap_review_screenshot(iap_id: str) -> None:
    img_bytes = IMAGE.read_bytes()
    payload = {
        "data": {
            "type": "inAppPurchaseAppStoreReviewScreenshots",
            "attributes": {
                "fileName": IMAGE.name,
                "fileSize": len(img_bytes),
            },
            "relationships": {
                "inAppPurchaseV2": {
                    "data": {"type": "inAppPurchases", "id": iap_id}
                }
            }
        }
    }
    r = requests.post(f"{BASE}/v1/inAppPurchaseAppStoreReviewScreenshots",
                      headers=H, data=json.dumps(payload))
    if r.status_code >= 300:
        print(f"  reserve fail: {r.status_code} {r.text[:300]}")
        return
    data = r.json()["data"]
    screenshot_id = data["id"]
    ops = data["attributes"]["uploadOperations"]
    print(f"  reserved id={screenshot_id} ops={len(ops)}")

    for op in ops:
        offset = op["offset"]
        length = op["length"]
        chunk = img_bytes[offset:offset + length]
        headers = {h["name"]: h["value"] for h in op["requestHeaders"]}
        rr = requests.request(op["method"], op["url"], headers=headers, data=chunk)
        if rr.status_code >= 300:
            print(f"  upload fail: {rr.status_code} {rr.text[:200]}")
            return

    checksum = md5_hex(IMAGE)
    patch = {
        "data": {
            "type": "inAppPurchaseAppStoreReviewScreenshots",
            "id": screenshot_id,
            "attributes": {
                "uploaded": True,
                "sourceFileChecksum": checksum,
            }
        }
    }
    r = requests.patch(f"{BASE}/v1/inAppPurchaseAppStoreReviewScreenshots/{screenshot_id}",
                       headers=H, data=json.dumps(patch))
    print(f"  commit: {r.status_code} {r.text[:200] if r.status_code >= 300 else 'OK'}")


def upload_sub_review_screenshot(sub_id: str) -> None:
    img_bytes = IMAGE.read_bytes()
    payload = {
        "data": {
            "type": "subscriptionAppStoreReviewScreenshots",
            "attributes": {
                "fileName": IMAGE.name,
                "fileSize": len(img_bytes),
            },
            "relationships": {
                "subscription": {
                    "data": {"type": "subscriptions", "id": sub_id}
                }
            }
        }
    }
    r = requests.post(f"{BASE}/v1/subscriptionAppStoreReviewScreenshots",
                      headers=H, data=json.dumps(payload))
    if r.status_code >= 300:
        print(f"  reserve fail: {r.status_code} {r.text[:300]}")
        return
    data = r.json()["data"]
    screenshot_id = data["id"]
    ops = data["attributes"]["uploadOperations"]
    print(f"  reserved id={screenshot_id} ops={len(ops)}")

    for op in ops:
        offset = op["offset"]
        length = op["length"]
        chunk = img_bytes[offset:offset + length]
        headers = {h["name"]: h["value"] for h in op["requestHeaders"]}
        rr = requests.request(op["method"], op["url"], headers=headers, data=chunk)
        if rr.status_code >= 300:
            print(f"  upload fail: {rr.status_code} {rr.text[:200]}")
            return

    checksum = md5_hex(IMAGE)
    patch = {
        "data": {
            "type": "subscriptionAppStoreReviewScreenshots",
            "id": screenshot_id,
            "attributes": {
                "uploaded": True,
                "sourceFileChecksum": checksum,
            }
        }
    }
    r = requests.patch(f"{BASE}/v1/subscriptionAppStoreReviewScreenshots/{screenshot_id}",
                       headers=H, data=json.dumps(patch))
    print(f"  commit: {r.status_code} {r.text[:200] if r.status_code >= 300 else 'OK'}")


if __name__ == "__main__":
    print("Pro Lifetime review screenshot:")
    upload_iap_review_screenshot(PRO_LIFETIME)
    print("Pro+ Monthly review screenshot:")
    upload_sub_review_screenshot(PROPLUS_MONTHLY)
    print("Pro+ Yearly review screenshot:")
    upload_sub_review_screenshot(PROPLUS_YEARLY)
