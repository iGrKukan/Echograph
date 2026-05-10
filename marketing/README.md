# Echograph — App Store launch kit

Все assets для подачи в App Store. Структура:

```
marketing/
├── app-store/
│   ├── en.md          ← App Store metadata, English (primary)
│   ├── ru.md          ← Russian
│   ├── de.md          ← German
│   ├── fr.md          ← French
│   └── ja.md          ← Japanese
├── screenshots/
│   ├── 01-home-en.png ← raw simulator screenshots, 1290×2796 (iPhone 17 Pro)
│   ├── 01-home-ru.png
│   ├── 01-home-de.png
│   ├── 01-home-fr.png
│   ├── 01-home-ja.png
│   └── app-store/     ← marketing-ready 1320×2868 with overlay headline
│       ├── 01-home-en-marketing.png
│       └── …
├── privacy-policy.md  ← публикуй на echograph.app/privacy
└── README.md          ← этот файл
```

## Что нужно ещё сделать вручную перед submission

### 1. Apple Developer Portal
- Зарегистрировать App ID `by.timberbid.echograph` (если ещё нет — он у нас уже в `project.yml`)
- Создать App Store provisioning profile (или использовать automatic signing)
- Включить capabilities: WhisperKit (нет специальных), Push Notifications (если будем добавлять — пока нет), iCloud (если будем включать sync — пока нет), App Group (для Live Activity widget — нужен когда раскомментим target)

### 2. App Store Connect — создать продукт
1. **Create New App** → Bundle ID: `by.timberbid.echograph`
2. Имя: `Echograph`
3. Primary language: English (U.S.)
4. SKU: `echograph-ios-001`
5. User Access: Full Access

### 3. App Store Connect — настроить продукты IAP
Создать в Apple Developer / App Store Connect → My Apps → Echograph → Features → In-App Purchases:

| Reference Name | Product ID | Type | Price |
|---|---|---|---|
| Pro Lifetime | `by.timberbid.echograph.pro.lifetime` | Non-Consumable | Tier 20 ($19.99) |
| Pro+ Monthly | `by.timberbid.echograph.proplus.monthly` | Auto-Renewable Subscription | Tier 5 ($4.99) |
| Pro+ Yearly | `by.timberbid.echograph.proplus.yearly` | Auto-Renewable Subscription | Tier 30 ($29.99), 7-day Free Trial |

Subscription Group: "Pro+"

### 4. Submit screenshots
- iPhone 6.9" (iPhone 17 Pro Max): загрузить из `screenshots/app-store/01-home-{lang}-marketing.png`
- Минимум 3, максимум 10 на размер
- Можно generate ещё через `xcrun simctl io booted screenshot` после ручной навигации

### 5. App Privacy questionnaire
Заполнить в App Store Connect → App Privacy:
- **Data Not Collected** — везде "No"
- "Does your app use third-party SDKs?" — Yes
  - WhisperKit (Argmax) — used to download/run Whisper models
  - swift-transformers, swift-crypto — transitive WhisperKit deps
  - Не собирают пользовательские данные (это on-device ML SDK)
- Privacy Manifest (`PrivacyInfo.xcprivacy`) — добавить файл который декларирует "Data Not Collected"

### 6. Publish privacy policy
Минимум вариант — захостить `privacy-policy.md` на:
- Netlify Drop (drag & drop, free, like ForestCalc.KubPro)
- GitHub Pages (если репо открыть)
- Своём домене echograph.app (когда купим)

URL подсунуть в App Store Connect → Privacy Policy URL.

### 7. Marketing URL и Support URL
- **Marketing URL**: одностраничный лендинг echograph.app — пока можно поставить URL Notion-страницы или Linktree
- **Support URL**: либо отдельная страница, либо `mailto:support@echograph.app`

### 8. Review notes (для Apple Reviewer)
В App Store Connect → App Information → App Review Information:
- **Sign-in required**: No
- **Demo account**: не нужно
- **Notes for Reviewer**:

> Echograph is a local voice recorder with on-device transcription using OpenAI's Whisper model (via WhisperKit/Argmax) and Apple Speech.
>
> To test:
> 1. Tap the red record button on the home screen, speak for 5+ seconds, tap again to stop.
> 2. Tap the new recording → tap "Transcribe" → choose "Apple Speech" for the fastest result, or "Whisper Small" (downloads ~244 MB, takes ~1-2 minutes on first run).
>
> All audio processing happens on-device. The app makes one network request — to download Whisper model weights from huggingface.co/argmaxinc/whisperkit-coreml on first use — then works offline.
>
> StoreKit Configuration is included for automated review. Tap "Whisper" without Pro → paywall opens; tap any product → simulated purchase via the included `.storekit` config; Whisper unlocks immediately.

### 9. Testing pre-submission
- TestFlight: 25 internal + до 10 000 external testers
- Прогнать на минимум 3 реальных iPhone разных поколений (старый iPhone 12 — Whisper Tiny, iPhone 15 Pro — Large v3 Turbo)
- Проверить Live Activity (раскомментить `target: EchographLiveActivity` в project.yml перед сборкой на реальное устройство)

### 10. Submission
1. Archive (Product → Archive в Xcode)
2. Distribute App → App Store Connect → Upload
3. Дождаться processing (5-30 мин)
4. В App Store Connect → Echograph → 0.1.0 → выбрать build → Submit for Review

Apple Review обычно 24-72 часа.

## Когда выложат — план первой недели

- День 0: Product Hunt launch (вторник, US утро)
- День 0-3: Reddit waves: r/apple → r/iphone → r/journalism → r/podcasting (нативно, без spam)
- День 1-7: Press push: TechCrunch, MacStories, 9to5Mac (через press kit)
- Apple ASA: бренд-биддинг на конкурентов ("Just Press Record", "Aiko", "Whisper Memos")

См. полный 90-day plan в основном README проекта.
