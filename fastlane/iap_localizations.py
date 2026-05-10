"""Add localizations to all 3 IAP products in 5 locales.

IAP/subscription locale limits: name 30 chars, description 45 chars.
"""
import sys, json, requests
sys.path.insert(0, "/Users/iharshkredau/Echograph/fastlane")
from asc_token import auth_headers

H = {**auth_headers(), "Content-Type": "application/json"}

PRO_LIFETIME = "6768049449"
PROPLUS_MONTHLY = "6768049087"
PROPLUS_YEARLY = "6768049481"

LOCALES = {
    "en-US": {
        "lifetime_name": "Voicekeep Pro",
        "lifetime_desc": "Whisper engines & custom vocabulary.",
        "monthly_name": "Voicekeep Pro+ Monthly",
        "monthly_desc": "AI summary, AI Q&A, auto-tags.",
        "yearly_name": "Voicekeep Pro+ Yearly",
        "yearly_desc": "AI summary, AI Q&A, auto-tags.",
    },
    "ru": {
        "lifetime_name": "Voicekeep Pro",
        "lifetime_desc": "Движки Whisper и свой словарь.",
        "monthly_name": "Voicekeep Pro+ месячная",
        "monthly_desc": "AI-резюме, Q&A, авто-теги.",
        "yearly_name": "Voicekeep Pro+ годовая",
        "yearly_desc": "AI-резюме, Q&A, авто-теги.",
    },
    "de-DE": {
        "lifetime_name": "Voicekeep Pro",
        "lifetime_desc": "Whisper-Engines & eigenes Vokabular.",
        "monthly_name": "Voicekeep Pro+ Monatlich",
        "monthly_desc": "AI-Zusammenfassung, Q&A, Auto-Tags.",
        "yearly_name": "Voicekeep Pro+ Jährlich",
        "yearly_desc": "AI-Zusammenfassung, Q&A, Auto-Tags.",
    },
    "fr-FR": {
        "lifetime_name": "Voicekeep Pro",
        "lifetime_desc": "Moteurs Whisper & vocabulaire perso.",
        "monthly_name": "Voicekeep Pro+ Mensuel",
        "monthly_desc": "Résumé IA, Q&R, tags auto.",
        "yearly_name": "Voicekeep Pro+ Annuel",
        "yearly_desc": "Résumé IA, Q&R, tags auto.",
    },
    "ja": {
        "lifetime_name": "Voicekeep Pro",
        "lifetime_desc": "Whisperエンジンとカスタム語彙。",
        "monthly_name": "Voicekeep Pro+ 月額",
        "monthly_desc": "AI要約、Q&A、自動タグ。",
        "yearly_name": "Voicekeep Pro+ 年額",
        "yearly_desc": "AI要約、Q&A、自動タグ。",
    },
}


def post_iap_loc(iap_id, locale, name, description):
    body = {
        "data": {
            "type": "inAppPurchaseLocalizations",
            "attributes": {"locale": locale, "name": name, "description": description},
            "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}}
        }
    }
    r = requests.post(
        "https://api.appstoreconnect.apple.com/v1/inAppPurchaseLocalizations",
        headers=H,
        data=json.dumps(body)
    )
    print(f"  IAP {iap_id} {locale} '{name}' ({len(name)}) / '{description}' ({len(description)})", r.status_code, "" if r.status_code < 300 else r.text[:200])


def post_sub_loc(sub_id, locale, name, description):
    body = {
        "data": {
            "type": "subscriptionLocalizations",
            "attributes": {"locale": locale, "name": name, "description": description},
            "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sub_id}}}
        }
    }
    r = requests.post(
        "https://api.appstoreconnect.apple.com/v1/subscriptionLocalizations",
        headers=H,
        data=json.dumps(body)
    )
    print(f"  Sub {sub_id} {locale} '{name}' ({len(name)}) / '{description}' ({len(description)})", r.status_code, "" if r.status_code < 300 else r.text[:200])


print("Pro Lifetime localizations:")
for locale, f in LOCALES.items():
    post_iap_loc(PRO_LIFETIME, locale, f["lifetime_name"], f["lifetime_desc"])

print("\nPro+ Monthly localizations:")
for locale, f in LOCALES.items():
    post_sub_loc(PROPLUS_MONTHLY, locale, f["monthly_name"], f["monthly_desc"])

print("\nPro+ Yearly localizations:")
for locale, f in LOCALES.items():
    post_sub_loc(PROPLUS_YEARLY, locale, f["yearly_name"], f["yearly_desc"])
