# Environment Config

Folder ini menyimpan konfigurasi sensitif (API secret, host, kredensial dev) yang **tidak boleh masuk git**. Hanya file `*.example` yang di-commit sebagai template.

## Struktur

- `dev.json` — config untuk development (gitignored)
- `prod.json` — config untuk production/release (gitignored)
- `dev.json.example` / `prod.json.example` — template tanpa nilai rahasia (di-commit)

## Cara pakai

Saat menjalankan / build aplikasi, gunakan flag `--dart-define-from-file`:

```bash
# Development (debug)
flutter run --dart-define-from-file=env/dev.json

# Production (release build APK)
flutter build apk --release --dart-define-from-file=env/prod.json

# iOS release
flutter build ipa --release --dart-define-from-file=env/prod.json
```

## Setup awal (tim baru)

```bash
cp env/dev.json.example env/dev.json
# Lalu isi nilai rahasia dari password manager / lead dev
```

## Field yang tersedia

| Key                  | Wajib | Keterangan                                                  |
| -------------------- | ----- | ----------------------------------------------------------- |
| `API_HOST`           | ya    | Host backend tanpa trailing slash (e.g. `https://api.x.com`) |
| `API_BASE_PATH`      | ya    | Path versi API, biasanya `/api/v1`                           |
| `API_SECRET`         | ya    | HMAC secret untuk header `X-SIGNATURE`                       |
| `DEV_LOGIN_EMAIL`    | tidak | Pre-fill login (debug mode saja)                             |
| `DEV_LOGIN_PASSWORD` | tidak | Pre-fill login (debug mode saja)                             |

## Catatan keamanan

- **JANGAN** commit `dev.json` / `prod.json` ke git.
- **JANGAN** kirim file ini lewat chat/email tanpa enkripsi. Gunakan password manager (1Password, Bitwarden) atau secret manager.
- Untuk CI/CD, set tiap key sebagai environment variable lalu generate file JSON saat build, atau gunakan `--dart-define=KEY=VALUE` per key.
- Ingat: nilai `--dart-define` **tetap embedded di binary** saat release. Untuk Flutter mobile tidak ada cara mencegah reverse engineering 100% — secret yang benar-benar rahasia harus tinggal di server, bukan di app.
