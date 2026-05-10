"""Upload App Store version metadata in 5 locales."""
import sys, json, requests
sys.path.insert(0, "/Users/iharshkredau/Echograph/fastlane")
from asc_token import auth_headers

VERSION_ID = "3eb0ccab-7b3e-4ff0-ab8f-79f3d95ec85d"
H = {**auth_headers(), "Content-Type": "application/json"}


# Apple-replaced "Echograph" with "Voicekeep" in promo text/keywords/description.
LOCALIZED = {
    "en-US": {
        "description": (
            "Voicekeep is a privacy-first voice recorder and transcriber. "
            "Audio is captured, transcribed, and summarized entirely on your iPhone — nothing is uploaded to any server.\n\n"
            "POWERED BY WHISPER\n"
            "Voicekeep runs OpenAI's Whisper speech-recognition model directly on Apple Neural Engine. "
            "State-of-the-art accuracy in 90+ languages, including English, Russian, German, French, Japanese, Korean, Chinese.\n\n"
            "WORKS WITHOUT INTERNET\n"
            "Once a Whisper model is downloaded, Voicekeep works fully offline. "
            "Useful on planes, in courtrooms, in clinics, in interviews — anywhere reliable Wi-Fi isn't.\n\n"
            "PROFESSIONAL FEATURES\n"
            "• Word-level timestamps with tap-to-seek playback\n"
            "• Search across every recording and transcript instantly\n"
            "• Edit transcript text to correct names and rare terms\n"
            "• Highlight key segments and filter by highlights\n"
            "• Manual speaker labels with color coding\n"
            "• Custom vocabulary biasing for legal, medical, and technical jargon\n"
            "• Export to PDF, Markdown, plain text, SRT, and VTT subtitles\n"
            "• Send transcript snippets to Reminders or Calendar with one tap\n"
            "• Translate any transcript using Apple's built-in Translation framework\n\n"
            "APPLE INTELLIGENCE INSIDE (Pro+)\n"
            "On iPhone 15 Pro and later running iOS 26, Voicekeep uses Apple's on-device language model to:\n"
            "• Generate concise meeting summaries with action items\n"
            "• Suggest topical tags automatically\n"
            "• Answer questions about any recording\n\n"
            "PRIVACY BY DESIGN\n"
            "• Audio is processed entirely on-device.\n"
            "• No analytics SDKs, no third-party trackers, no data collection.\n"
            "• Apple Privacy Label: \"Data Not Collected\".\n"
            "• Open-source Whisper models. You can audit what runs.\n\n"
            "Your voice. Your iPhone. Nothing else."
        ),
        "keywords": "transcribe,voice,recorder,whisper,speech to text,dictation,interview,meeting,offline,privacy",
        "promotionalText": "Whisper-quality transcription that runs entirely on your iPhone. No cloud, no upload, no paid minutes — just press record.",
        "marketingUrl": "https://igrkukan.github.io/Echograph/",
        "supportUrl": "https://igrkukan.github.io/Echograph/support.html",
        "whatsNew": "Initial release. Press record, get a Whisper transcript, search and export — all on-device."
    },
    "ru": {
        "description": (
            "Voicekeep — диктофон с распознаванием речи, который не отправляет ваш голос в облако. "
            "Запись, транскрипция и AI-резюме — всё работает на вашем iPhone.\n\n"
            "WHISPER ВНУТРИ\n"
            "В основе Voicekeep — модель OpenAI Whisper, запущенная нативно на Apple Neural Engine. "
            "Современное качество распознавания в 90+ языках, включая русский, английский, немецкий, "
            "французский, японский, корейский, китайский.\n\n"
            "РАБОТАЕТ БЕЗ ИНТЕРНЕТА\n"
            "После однократной загрузки модели Whisper приложение полностью офлайн. "
            "Удобно в самолёте, в зале суда, в клинике, в командировке.\n\n"
            "ПРОФЕССИОНАЛЬНЫЕ ФУНКЦИИ\n"
            "• Транскрипт с таймкодами для каждого слова и тапом для перемотки\n"
            "• Мгновенный поиск по всем записям и транскриптам\n"
            "• Редактирование текста для исправления имён и редких терминов\n"
            "• Выделение важных фрагментов и фильтр по выделениям\n"
            "• Метки спикеров с цветовой палитрой\n"
            "• Свой словарь терминов для биасинга Whisper под медицинскую, юридическую, техническую лексику\n"
            "• Экспорт в PDF, Markdown, TXT, SRT и VTT субтитры\n"
            "• Отправка фрагмента в Напоминания или Календарь одним тапом\n"
            "• Перевод транскрипта через нативный Apple Translation\n\n"
            "APPLE INTELLIGENCE (тариф Pro+)\n"
            "На iPhone 15 Pro и новее с iOS 26 Voicekeep использует локальную языковую модель Apple для:\n"
            "• Сжатого резюме встречи с пунктами действий\n"
            "• Автоматических тематических тегов\n"
            "• Ответов на вопросы по записи\n\n"
            "ПРИВАТНОСТЬ КАК ОСНОВА\n"
            "• Аудио обрабатывается только на устройстве.\n"
            "• Никаких аналитических SDK, никаких сторонних трекеров, никакого сбора данных.\n"
            "• Apple Privacy Label: «Данные не собираются».\n\n"
            "Ваш голос. Ваш iPhone. Ничего лишнего."
        ),
        "keywords": "распознавание,диктофон,whisper,текст,субтитры,интервью,совещание,лекция,офлайн,приватность",
        "promotionalText": "Whisper-уровень распознавания, полностью на вашем iPhone. Без облака, без загрузки, без платных минут.",
        "marketingUrl": "https://igrkukan.github.io/Echograph/",
        "supportUrl": "https://igrkukan.github.io/Echograph/support.html",
        "whatsNew": "Первый релиз. Нажмите запись — получите Whisper-транскрипт, поиск и экспорт. Всё на iPhone."
    },
    "de-DE": {
        "description": (
            "Voicekeep ist ein datenschutzfreundlicher Sprachrekorder mit Transkription. "
            "Audio wird vollständig auf deinem iPhone aufgenommen, transkribiert und zusammengefasst — kein Server, kein Upload.\n\n"
            "WHISPER LÄUFT LOKAL\n"
            "Voicekeep nutzt OpenAIs Whisper-Modell direkt auf der Apple Neural Engine. "
            "Modernste Erkennungsqualität in 90+ Sprachen.\n\n"
            "OHNE INTERNET\n"
            "Nach einmaligem Download des Whisper-Modells funktioniert Voicekeep komplett offline.\n\n"
            "PROFI-FEATURES\n"
            "• Wort-genaue Zeitstempel mit Tap-to-Seek\n"
            "• Sofortsuche über alle Aufnahmen\n"
            "• Transkripte editieren\n"
            "• Wichtige Stellen markieren\n"
            "• Manuelle Sprecher-Labels\n"
            "• Eigenes Vokabular für Fachbegriffe\n"
            "• Export nach PDF, Markdown, TXT, SRT, VTT\n"
            "• Erinnerungen oder Kalender mit einem Tipp\n"
            "• Apple Translation Integration\n\n"
            "APPLE INTELLIGENCE (Pro+)\n"
            "Auf iPhone 15 Pro und neuer mit iOS 26: Meeting-Zusammenfassungen, Auto-Tags, Fragen zur Aufnahme.\n\n"
            "DATENSCHUTZ\n"
            "Audio wird ausschließlich am Gerät verarbeitet. Keine Analytics-SDKs, keine Tracker.\n\n"
            "Deine Stimme. Dein iPhone. Mehr nicht."
        ),
        "keywords": "diktiergerät,sprache zu text,whisper,transkript,untertitel,interview,meeting,offline,datenschutz",
        "promotionalText": "Whisper-Qualität direkt am iPhone. Ohne Cloud, ohne Upload, ohne Minutenpreise.",
        "marketingUrl": "https://igrkukan.github.io/Echograph/",
        "supportUrl": "https://igrkukan.github.io/Echograph/support.html",
        "whatsNew": "Erstveröffentlichung. Aufnahme drücken, Whisper-Transkript bekommen, suchen, exportieren — alles am Gerät."
    },
    "fr-FR": {
        "description": (
            "Voicekeep est un enregistreur vocal respectueux de la vie privée. "
            "L'audio est capturé, transcrit et résumé entièrement sur votre iPhone — rien n'est envoyé sur un serveur.\n\n"
            "WHISPER EN LOCAL\n"
            "Voicekeep exécute le modèle Whisper d'OpenAI sur l'Apple Neural Engine. "
            "Précision à l'état de l'art dans 90+ langues.\n\n"
            "FONCTIONNE SANS INTERNET\n"
            "Après le téléchargement du modèle, Voicekeep fonctionne entièrement hors ligne.\n\n"
            "FONCTIONS PROFESSIONNELLES\n"
            "• Horodatage au mot près avec lecture par tap\n"
            "• Recherche instantanée\n"
            "• Édition de la transcription\n"
            "• Surlignage des passages clés\n"
            "• Étiquettes d'intervenants colorées\n"
            "• Vocabulaire personnalisé\n"
            "• Export PDF, Markdown, TXT, SRT, VTT\n"
            "• Rappels ou Calendrier en un appui\n"
            "• Apple Translation intégrée\n\n"
            "APPLE INTELLIGENCE (Pro+)\n"
            "Sur iPhone 15 Pro et plus récent avec iOS 26 : résumés de réunion, tags automatiques, questions sur la transcription.\n\n"
            "Votre voix. Votre iPhone. Rien d'autre."
        ),
        "keywords": "dictaphone,transcription,whisper,sous-titres,interview,réunion,hors ligne,vie privée",
        "promotionalText": "Qualité Whisper, entièrement sur votre iPhone. Pas de cloud, pas d'upload, pas de minutes payantes.",
        "marketingUrl": "https://igrkukan.github.io/Echograph/",
        "supportUrl": "https://igrkukan.github.io/Echograph/support.html",
        "whatsNew": "Première version. Appuyez sur enregistrer, obtenez une transcription Whisper, cherchez, exportez — tout sur l'appareil."
    },
    "ja": {
        "description": (
            "Voicekeepはプライバシーを最優先に設計された音声録音・文字起こしアプリです。"
            "録音、文字起こし、要約 — すべてiPhone上で完結し、外部サーバーには一切送信されません。\n\n"
            "WHISPERがローカル\n"
            "VoicekeepはOpenAIのWhisperモデルをApple Neural Engine上で実行します。"
            "90以上の言語で最先端の精度。\n\n"
            "オフラインで完全動作\n"
            "Whisperモデルをダウンロードすれば完全オフライン。\n\n"
            "プロフェッショナル機能\n"
            "• 単語単位のタイムスタンプとタップ再生\n"
            "• 瞬時の横断検索\n"
            "• 文字起こしの編集\n"
            "• 重要箇所のハイライト\n"
            "• 話者ラベル\n"
            "• カスタム語彙\n"
            "• PDF / Markdown / TXT / SRT / VTTエクスポート\n"
            "• ワンタップでリマインダー・カレンダーへ\n"
            "• Apple純正翻訳との連携\n\n"
            "APPLE INTELLIGENCE (Pro+)\n"
            "iPhone 15 Pro以降 / iOS 26環境では会議要約、自動タグ、録音への質疑応答。\n\n"
            "あなたの声。あなたのiPhone。それだけ。"
        ),
        "keywords": "文字起こし,録音,whisper,音声認識,会議,インタビュー,議事録,字幕,オフライン,プライバシー",
        "promotionalText": "WhisperクオリティをiPhoneだけで。クラウドなし、アップロードなし、分課金なし。",
        "marketingUrl": "https://igrkukan.github.io/Echograph/",
        "supportUrl": "https://igrkukan.github.io/Echograph/support.html",
        "whatsNew": "初回リリース。録音ボタンを押せば、Whisper文字起こし、検索、エクスポート、すべてiPhone上で完結します。"
    }
}


# Get current localizations
r = requests.get(
    f"https://api.appstoreconnect.apple.com/v1/appStoreVersions/{VERSION_ID}/appStoreVersionLocalizations",
    headers=auth_headers()
)
existing = {l['attributes']['locale']: l['id'] for l in r.json().get("data", [])}
print("Existing version locales:", list(existing.keys()))

for locale, fields in LOCALIZED.items():
    # whatsNew is only valid for updates after 1.0; skip on initial release.
    attrs = {
        "description": fields["description"],
        "keywords": fields["keywords"],
        "promotionalText": fields["promotionalText"],
        "marketingUrl": fields["marketingUrl"],
        "supportUrl": fields["supportUrl"]
    }
    if locale in existing:
        loc_id = existing[locale]
        r = requests.patch(
            f"https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations/{loc_id}",
            headers=H,
            data=json.dumps({"data": {"type": "appStoreVersionLocalizations", "id": loc_id, "attributes": attrs}})
        )
        print(f"  [PATCH {locale}]", r.status_code, "" if r.status_code < 300 else r.text[:200])
    else:
        r = requests.post(
            "https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations",
            headers=H,
            data=json.dumps({
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "attributes": {**attrs, "locale": locale},
                    "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": VERSION_ID}}}
                }
            })
        )
        print(f"  [POST {locale}]", r.status_code, "" if r.status_code < 300 else r.text[:200])
