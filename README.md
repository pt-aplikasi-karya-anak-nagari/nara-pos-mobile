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

## Menjalankan & build (dev / prod)

Alamat server ada di berkas env (`env/README.md`): `env/dev.json` (per PC, tidak
di-commit) dan `env/prod.json`. Tiap skrip punya versi bash (`.sh`) dan
PowerShell (`.ps1`, Windows: `powershell -ExecutionPolicy Bypass -File scripts\<nama>.ps1`).

| Tujuan | Skrip | Hasil |
|---|---|---|
| Isi IP PC ke `env/dev.json` | `set_dev_ip` | API `http://<IP>:3001`, web `:3000` |
| Jalankan debug ke server dev | `run_dev` | `flutter run` + `env/dev.json` |
| Debug lewat kabel USB (Windows) | `run_dev_windows.ps1` | `adb reverse` + `127.0.0.1` |
| APK uji ke server dev | `build_dev` | `build/app/outputs/flutter-apk/app-debug.apk` |
| Jalankan release ke produksi | `run_prod` | butuh `NARA_API_SECRET` |
| Build rilis (Play Store) | `build_prod` | APK/AAB ber-obfuscate, butuh `NARA_API_SECRET` & `android/key.properties` |

```bash
./scripts/set_dev_ip.sh && ./scripts/run_dev.sh
NARA_API_SECRET='...' TARGET=appbundle ./scripts/build_prod.sh
```

```powershell
powershell -ExecutionPolicy Bypass -File scripts\set_dev_ip.ps1
powershell -ExecutionPolicy Bypass -File scriptsun_dev.ps1
$env:NARA_API_SECRET = '...'
powershell -ExecutionPolicy Bypass -File scriptsuild_prod.ps1 -Target appbundle
```

`build_prod` menolak build bila `env/prod.json` bukan `https://` / masih IP
lokal, secret kosong atau masih secret dev. App rilis juga menolak start bila
alamatnya lokal. `flutter run` polos dari IDE tetap jalan dengan alamat bawaan
di `lib/core/config/app_config.dart`.

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

ID aplikasi **saat ini masih bawaan example** (sementara, supaya cocok dengan
file Firebase yang ada): Android `com.example.nara_pos_mobile`, iOS
`com.example.naraPosMobile`. **Play Store menolak ID `com.example`**, dan ID
tak bisa diubah setelah terbit — ganti ke ID final (rencana: `id.nara.pos`)
sebelum rilis pertama.

### 1. Ganti ke ID final + Firebase (sekali saja, sebelum rilis)

1. Ubah `namespace` & `applicationId` di `android/app/build.gradle.kts`,
   package Kotlin di `android/app/src/main/kotlin/`, dan
   `PRODUCT_BUNDLE_IDENTIFIER` di `ios/Runner.xcodeproj/project.pbxproj`.
2. Daftarkan app ID final di Firebase project `nara-pos` & buat ulang
   `google-services.json`, `GoogleService-Info.plist`,
   `lib/firebase_options.dart`:

```bash
npm install -g firebase-tools && firebase login
dart pub global activate flutterfire_cli
flutterfire configure --project=nara-pos --platforms=android,ios \n  --android-package-name=id.nara.pos --ios-bundle-id=id.nara.pos
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
