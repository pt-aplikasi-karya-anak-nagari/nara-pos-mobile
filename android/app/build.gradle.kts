// Diimpor eksplisit: di skrip Gradle, `java` merujuk ekstensi Gradle `java`,
// bukan paket java.util — `java.util.Properties()` gagal dikompilasi.
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ─── Kunci tanda tangan rilis ───────────────────────────────────────────
// Dibaca dari android/key.properties (TIDAK di-commit, lihat android/.gitignore):
//   storeFile=/path/absolut/nara-upload.jks
//   storePassword=...
//   keyAlias=nara-upload
//   keyPassword=...
// Build rilis (assembleRelease / bundleRelease) GAGAL kalau file ini tak ada,
// supaya APK/AAB bertanda tangan kunci debug tidak pernah ikut terbit.
// Cara membuat keystore: lihat README.md bagian "Rilis Android".
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { stream -> keystoreProperties.load(stream) }
}
val memintaBuildRilis = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}
if (memintaBuildRilis && !keystorePropertiesFile.exists()) {
    throw GradleException(
        "android/key.properties tidak ditemukan. Build rilis wajib ditandatangani " +
            "kunci upload sendiri, bukan kunci debug. Lihat README.md bagian \"Rilis Android\".",
    )
}

android {
    namespace = "com.example.nara_pos_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Dibutuhkan oleh flutter_local_notifications (memakai java.time API
        // yang perlu di-desugar untuk minSdk lama).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // SEMENTARA: ID bawaan example, cocok dengan google-services.json yang ada.
        // Ganti ke ID final (mis. id.nara.pos) + flutterfire configure SEBELUM
        // rilis ke Play Store — ID tak bisa diubah setelah terbit.
        applicationId = "com.example.nara_pos_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Library desugaring untuk flutter_local_notifications (java.time, dll).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}