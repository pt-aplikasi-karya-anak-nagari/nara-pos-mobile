# Berkas env aplikasi kasir

Dibaca `flutter` lewat `--dart-define-from-file` oleh skrip di `scripts/`.

| Berkas | Mode | Di-commit? |
|---|---|---|
| `dev.json` | debug/profile — `run_dev`, `build_dev` | **Tidak** (alamat PC masing-masing). Dibuat otomatis dari `dev.example.json`; `set_dev_ip` mengisi IP Wi-Fi PC. |
| `prod.json` | rilis — `run_prod`, `build_prod` | Ya. Wajib `https://` dan bukan IP lokal (diperiksa `build_prod`). |

Kunci:

- `NARA_API_HOST` — host backend tanpa `/` di akhir, mis. `http://192.168.1.22:3001`.
- `NARA_WEB_URL` — dashboard web (halaman daftar, panduan hapus akun).
- `NARA_MENU_QR_URL` — halaman menu QR pelanggan (`<web>/menu`).

Rahasia **tidak** ditaruh di sini: `NARA_API_SECRET` (= `API_SECRET_KEY` server
produksi) diberikan sebagai variabel lingkungan saat `run_prod` / `build_prod`.
Lihat juga `lib/core/config/app_config.dart`.
