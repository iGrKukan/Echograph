"""Upload App Store screenshots for all locales."""
import sys, json, requests, hashlib
from pathlib import Path
sys.path.insert(0, "/Users/iharshkredau/Echograph/fastlane")
from asc_token import auth_headers

H = {**auth_headers(), "Content-Type": "application/json"}

VERSION_LOCALES = json.load(open("/Users/iharshkredau/Echograph/fastlane/secrets/version_locale_ids.json"))
SCREENSHOT_DIR = Path("/Users/iharshkredau/Echograph/marketing/screenshots/app-store")

# Apple iPhone 6.9" display screenshot type
DISPLAY_TYPE = "APP_IPHONE_67"  # 6.9" current Apple naming for iPhone 17 Pro Max class

LOCALE_FILES = {
    "en-US": "01-home-en-marketing.png",
    "ru": "01-home-ru-marketing.png",
    "de-DE": "01-home-de-marketing.png",
    "fr-FR": "01-home-fr-marketing.png",
    "ja": "01-home-ja-marketing.png",
}


def get_or_create_screenshot_set(loc_id, display_type):
    r = requests.get(
        f"https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets",
        headers=auth_headers()
    )
    for s in r.json().get("data", []):
        if s["attributes"]["screenshotDisplayType"] == display_type:
            return s["id"]
    body = {
        "data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": display_type},
            "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}
        }
    }
    r = requests.post(
        "https://api.appstoreconnect.apple.com/v1/appScreenshotSets",
        headers=H,
        data=json.dumps(body)
    )
    if r.status_code in (200, 201):
        return r.json()["data"]["id"]
    print("Failed creating screenshot set:", r.text[:300])
    return None


def upload_screenshot(set_id, file_path):
    file_path = Path(file_path)
    file_size = file_path.stat().st_size
    file_name = file_path.name

    # 1. Reserve
    body = {
        "data": {
            "type": "appScreenshots",
            "attributes": {"fileSize": file_size, "fileName": file_name},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}
        }
    }
    r = requests.post(
        "https://api.appstoreconnect.apple.com/v1/appScreenshots",
        headers=H,
        data=json.dumps(body)
    )
    if r.status_code not in (200, 201):
        print(f"  Reserve failed:", r.status_code, r.text[:300])
        return False
    asset = r.json()["data"]
    asset_id = asset["id"]
    upload_ops = asset["attributes"]["uploadOperations"]

    # 2. PUT file chunks
    with open(file_path, "rb") as f:
        data = f.read()
    for op in upload_ops:
        method = op["method"]
        url = op["url"]
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        offset = op.get("offset", 0)
        length = op.get("length", file_size)
        chunk = data[offset:offset + length]
        r = requests.request(method, url, headers=headers, data=chunk)
        if r.status_code >= 300:
            print(f"  PUT failed:", r.status_code, r.text[:200])
            return False

    # 3. Commit (md5)
    md5 = hashlib.md5(data).hexdigest()
    body = {
        "data": {
            "type": "appScreenshots",
            "id": asset_id,
            "attributes": {"uploaded": True, "sourceFileChecksum": md5}
        }
    }
    r = requests.patch(
        f"https://api.appstoreconnect.apple.com/v1/appScreenshots/{asset_id}",
        headers=H,
        data=json.dumps(body)
    )
    if r.status_code in (200, 201):
        print(f"  ✓ uploaded {file_name} ({file_size} bytes)")
        return True
    print(f"  Commit failed:", r.status_code, r.text[:300])
    return False


for locale, fname in LOCALE_FILES.items():
    loc_id = VERSION_LOCALES.get(locale)
    if not loc_id:
        print(f"No localization for {locale}")
        continue
    print(f"\n[{locale}]")
    set_id = get_or_create_screenshot_set(loc_id, DISPLAY_TYPE)
    if not set_id:
        continue
    file_path = SCREENSHOT_DIR / fname
    if not file_path.exists():
        print(f"  File missing: {file_path}")
        continue
    upload_screenshot(set_id, file_path)
