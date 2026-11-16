# Aturan R8 tambahan untuk build rilis (lihat buildTypes.release di
# build.gradle.kts). Flutter Gradle Plugin & tiap plugin sudah membawa aturan
# "consumer" masing-masing; di sini hanya yang tidak mereka bawa.

# Flutter engine merujuk Play Core (deferred components) secara opsional.
# Aplikasi ini tidak memakainya; tanpa baris ini R8 gagal karena kelasnya tak ada.
-dontwarn com.google.android.play.core.**

# Channel native milik aplikasi (dipanggil dari Dart lewat MethodChannel).
# Namanya boleh diacak, tapi kelasnya jangan dibuang.
-keep class com.example.nara_pos_mobile.MainActivity { *; }

# Hapus log Android di rilis — pesan log bisa membuka alur internal aplikasi.
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}

# Simpan nomor baris untuk laporan crash Sentry, tapi sembunyikan nama file asli.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
