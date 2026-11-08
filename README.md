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

## Rilis Android

ID aplikasi: **`id.nara.pos`** (Android `applicationId` & iOS bundle ID).
Permanen setelah terbit di Play Store — jangan diubah.

### 1. Firebase untuk ID baru (sekali saja)

`google-services.json`, `GoogleService-Info.plist`, dan
`lib/firebase_options.dart` terikat ke ID aplikasi. Daftarkan app
`id.nara.pos` (Android & iOS) di Firebase project `nara-pos`, lalu:

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=nara-pos
```

### 2. Kunci upload (sekali saja — SIMPAN BAIK-BAIK)

Kunci ini tidak bisa diganti sendiri; kalau hilang, update aplikasi tidak
bisa diunggah. Simpan file `.jks` + password-nya di password manager /
brankas, di luar repo.

```bash
keytool -genkeypair -v -keystore ~/nara-upload.jks -alias nara-upload \
  -keyalg RSA -keysize 2048 -validity 10000
```

Buat `android/key.properties` (sudah di `.gitignore`, JANGAN di-commit):

```properties
storeFile=/path/absolut/ke/nara-upload.jks
storePassword=...
keyAlias=nara-upload
keyPassword=...
```

Aktifkan **Play App Signing** saat membuat aplikasi di Play Console.

### 3. Build

```bash
NARA_API_SECRET='<API_SECRET_KEY server produksi>' \
  TARGET=appbundle ./scripts/build_prod.sh
```

Skrip menolak build kalau secret kosong/masih secret dev, kalau
`key.properties` tidak ada, atau kalau alamat server rilis bukan `https://`.
Naikkan `version:` di `pubspec.yaml` (angka setelah `+` wajib naik) tiap
unggahan ke Play Store.

### 4. Paksa update (versi minimum)

Aplikasi mengirim nomor build (angka setelah `+` di `version:`) di header
`X-App-Build`. Untuk mewajibkan semua tablet memakai build terbaru, set di
server `MOBILE_MIN_BUILD=<build>` (dan `MOBILE_UPDATE_URL` bila bukan Play
Store). Build lebih lama langsung menampilkan layar **Perbarui aplikasi**;
transaksi offline di perangkat ditahan dan terkirim setelah update.
Naikkan `MOBILE_MIN_BUILD` hanya SETELAH build baru tersedia di Play Store.
