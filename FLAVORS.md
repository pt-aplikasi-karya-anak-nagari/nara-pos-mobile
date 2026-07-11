# Environment / Flavor — Dev & Prod

NARA POS mobile membedakan environment **dev** vs **prod** lewat pendekatan
**runtime** memakai paket [`flutter_flavor`](https://pub.dev/packages/flutter_flavor)
`^3.1.4` (banner env di layar) + konfigurasi via **`--dart-define-from-file`**.

Selaras dengan repo lain:

| Layer | Sumber env | Nilai |
|---|---|---|
| Backend (Go) | `SERVER_ENVIRONMENT` | `development` / `production` |
| Web (Next.js) | `.env.local` → `NEXT_PUBLIC_API_HOST` dll | host dev / prod |
| **Mobile (ini)** | **`APP_ENV`** (+ `API_HOST`, `API_SECRET`…) via `--dart-define-from-file` | **`dev` / `prod`** |

> ℹ️ Pendekatan ini **runtime-only** — tidak membuat Android product-flavor /
> iOS scheme terpisah, jadi tidak ada bundle-id per-flavor (tidak bisa dev & prod
> terpasang berdampingan). Cukup untuk memisahkan konfigurasi & memberi indikator
> visual. Kalau butuh install berdampingan, beri tahu — bisa ditambah native
> flavor terpisah.

---

## Cara pakai

```bash
./scripts/run_dev.sh      # dev — banner "DEV" di sudut, backend LAN
./scripts/run_prod.sh     # prod — tanpa banner, backend produksi

./scripts/build_prod.sh                    # build APK prod
TARGET=appbundle ./scripts/build_prod.sh   # .aab (Play Store)
TARGET=ipa       ./scripts/build_prod.sh   # iOS
```

Setara dengan perintah manual:

```bash
flutter run                 --dart-define-from-file=env/dev.json
flutter build apk --release --dart-define-from-file=env/prod.json
```

---

## Bagaimana kerjanya

1. **`env/dev.json` / `env/prod.json`** (gitignored) memuat `APP_ENV` + host/secret:
   ```jsonc
   {
     "APP_ENV": "dev",                 // "dev" | "prod"
     "API_HOST": "http://192.0.18.51:3001",
     "API_BASE_PATH": "/api/v1",
     "API_SECRET": "…",
     "NARA_SCAN_QR_BASE_URL": "…"
   }
   ```
2. **`AppConfig`** (`lib/core/config/app_config.dart`) membaca `APP_ENV` →
   `AppConfig.flavor` (`Flavor.dev` / `Flavor.prod`), `isProd`, `flavorLabel`,
   plus host/secret API.
3. **`main.dart`** menginisialisasi `FlavorConfig` (flutter_flavor) dari
   `AppConfig`:
   ```dart
   FlavorConfig(
     name: AppConfig.isProd ? '' : AppConfig.flavor.id.toUpperCase(), // '' = prod tanpa banner
     color: const Color(0xFFB0231F),
     location: BannerLocation.topEnd,
     variables: { 'env': AppConfig.flavorLabel, 'apiBaseUrl': AppConfig.apiBaseUrl },
   );
   ```
   Lalu mencetak log: `[NARA] flavor=dev (Development) · API=…` dan
   **memperingatkan** kalau flavor `prod` tapi host masih http/LAN.
4. **`app.dart`** membungkus app dengan `FlavorBanner(child: …)` — ribbon muncul
   HANYA bila `FlavorConfig.name` tidak kosong (jadi **prod bersih**).

Akses di mana saja: `FlavorConfig.instance.variables['apiBaseUrl']`,
`FlavorConfig.instance.name`, atau langsung `AppConfig.isProd` / `AppConfig.apiBaseUrl`.

---

## Checklist rilis produksi

- [ ] `env/prod.json`: `APP_ENV="prod"`, `API_HOST` = **https** domain produksi,
      `API_SECRET` = secret produksi (match `API_SECRET_KEY` backend).
- [ ] Build via `./scripts/build_prod.sh`.
- [ ] Cek log start: `flavor=prod (Production)` tanpa warning.
- [ ] Tidak ada ribbon "DEV" di app.
