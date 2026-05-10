# Echograph

iOS-приложение: диктофон с локальной транскрипцией через Whisper и on-device диаризацией.

> Your voice. Your device. Nothing else.

## Что делаем

100% on-device транскрибатор и диктофон. Никаких облачных сервисов, никаких отправок аудио наружу. Whisper Large v3 Turbo + Apple SpeechAnalyzer + on-device speaker diarization.

## Стек

- **Swift 6, SwiftUI**, iOS 17+ (full features iOS 26+)
- **AVAudioEngine** — запись 48 kHz / 24-bit
- **WhisperKit** (Argmax) — основной транскрибатор, Whisper Large v3 Turbo q5_0
- **Apple SpeechAnalyzer** (iOS 26) — fallback для Free tier и быстрых live-транскриптов
- **ECAPA-TDNN-mini** + spectral clustering — диаризация on-device
- **Apple Foundation Models** — суммаризация и action items в Pro+ tier
- **GRDB.swift** (SQLite) — локальная база
- **CloudKit + CryptoKit** — опциональная E2EE-синхронизация

## Сборка

Проект генерируется XcodeGen из `project.yml`:

```bash
brew install xcodegen   # если ещё не установлен
cd ~/Echograph
xcodegen generate
open Echograph.xcodeproj
```

Bundle ID: `by.timberbid.echograph`. Team ID: `ZVYKY9TF2X`.

## Структура

```
Echograph/
├── App/                 # entry point
├── Core/Models/         # Recording, Transcript, Speaker
├── Audio/               # AVAudioEngine recording
├── Transcription/       # WhisperKit + SpeechAnalyzer
├── UI/                  # SwiftUI screens
│   └── Components/
└── Resources/           # assets
```

## Roadmap

### Sprint 1 (нед. 1-2) — каркас и запись ✅
- [x] XcodeGen + SwiftUI скелет
- [x] AVAudioRecorder m4a (44.1 kHz mono AAC 64 kbps)
- [x] Список записей + детальный экран с проигрывателем
- [x] Локальное хранилище в JSON (GRDB отложен — переусложнение для MVP)
- [x] Permission flow для микрофона

### Sprint 2 (нед. 3-4) — транскрипция MVP ✅
- [x] Apple Speech (SFSpeechRecognizer, on-device, iOS 17+)
- [x] WhisperKit 0.18.0 (Tiny / Base / Small / Large v3 Turbo)
- [x] Авто-выбор модели по RAM устройства
- [x] Скачивание Whisper-модели через WhisperKit при первом использовании
- [x] Word-level timestamps + tap-to-seek
- [x] Поиск по транскриптам (full-text)
- [x] Подсветка активного сегмента + автоскролл

### Sprint 3 (нед. 5-6) — Apple platforms ✅
- [x] Live Activity / Dynamic Island во время записи
- [x] Lock Screen widget (через Live Activity)
- [x] Экспорт: .txt, .md, .srt, .vtt, .pdf
- [x] Action Button quick-record (App Intent + Siri Shortcut)
- [x] watchOS standalone app (код готов; embed disabled — нужен watchOS Simulator runtime через Xcode › Settings › Components, ~3 GB)
- [ ] .docx экспорт (требует ZIP/XML — отложено в Pro tier)

### Sprint 4 (нед. 7-8) — paywall и Pro+ ✅
- [x] StoreKit 2: Pro $19.99 lifetime + Pro+ $4.99/мес или $29.99/yr (7-day trial)
- [x] PaywallView, PurchaseManager, restore, listen for updates
- [x] StoreKit Configuration файл для тестирования в симуляторе
- [x] Apple Foundation Models — AI Summary в Pro+ (iOS 26+ Apple Intelligence)
- [x] Whisper-движки гейтятся за Pro

### Sprint 5 — Power user features ✅
- [x] Copy / Share / Edit сегмента через context menu
- [x] Highlights с фильтром «Show only highlights»
- [x] Add to Reminders (EventKit)
- [x] Tags с поиском по `#tag`
- [x] Speaker labels (manual diarization), цветные badges
- [x] Custom Vocabulary — Whisper promptTokens biasing
- [x] AI Q&A через Apple Foundation Models (Pro+)
- [x] Translate transcript через Apple Translation API
- [x] Auto-suggest tags (Apple Intelligence, Pro+)
- [x] Add to Calendar (EventKit)

### Sprint 6 — Polish & Localization ✅
- [x] Settings экран (default language, custom vocabulary, subscription, version)
- [x] Pulse-анимация на REC button во время записи
- [x] Blinking dot на индикаторе записи
- [x] Spring-анимации появления индикатора
- [x] Localizable.xcstrings с EN/RU/DE/FR/JA для 60+ строк UI
- [x] knownRegions + LOCALIZATION_PREFERS_STRING_CATALOGS

### Backlog
- [ ] Apple Pencil annotations (iPad-only Sprint)
- [ ] Auto-diarization (ECAPA-TDNN CoreML модель)
- [ ] Multi-recording semantic search (embeddings)
- [ ] Studio mode для подкастеров (multi-track)
- [ ] Asset catalog с настоящими AppIcon assets
- [ ] App Store screenshots и submission

## Локализация Day 1

en-US, en-GB, ja-JP, de-DE, fr-FR, ru-RU, ko-KR

## Цены

| Tier | Что | Цена |
|------|-----|------|
| Free | Apple SpeechAnalyzer, 30 мин/запись, 5/день | $0 |
| Pro | Whisper Large v3 Turbo + диаризация + экспорт + watchOS | $19.99 lifetime |
| Pro+ | AI summary + custom vocab + Apple Pencil + multi-track + E2EE sync | $29.99/yr или $4.99/мес |
| Enterprise | MDM-ready, BAA по запросу | $9.99/seat/мес |
