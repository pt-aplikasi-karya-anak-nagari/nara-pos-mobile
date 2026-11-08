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
val keystoreProperties = java.util.Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
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
    namespace = "id.nara.pos"
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
        // ID aplikasi permanen di Play Store — JANGAN diubah setelah terbit.
        applicationId = "id.nara.pos"
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