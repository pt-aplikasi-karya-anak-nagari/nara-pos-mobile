# nara_pos_mobile

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
# nara-pos

## Pelaporan crash (Sentry)

Opsional — tanpa DSN, Sentry tidak dinyalakan. DSN dibaca saat build:

```bash
./scripts/build_prod.sh --dart-define=SENTRY_DSN=https://...@....ingest.sentry.io/... \
  --dart-define=SENTRY_ENVIRONMENT=production
```

Yang dikirim hanya crash & galat tak tertangani, tanpa isi `debugPrint`,
screenshot, request, maupun data pengguna selain id — lihat
`lib/core/pantau.dart`. Event saat offline dikirim begitu tablet online.
