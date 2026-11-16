package com.example.nara_pos_mobile

import android.app.Activity
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * Pemeriksaan integritas perangkat & aplikasi (anti-root, anti-debug,
 * anti-hooking, anti-emulator, anti-repackaging) untuk
 * lib/core/keamanan/integritas_perangkat.dart.
 *
 * Kanal ini HANYA MELAPORKAN temuan; keputusan memblokir ada di Dart supaya
 * kebijakannya bisa dites dan sama dengan iOS.
 *
 * Batasannya jujur: semua pemeriksaan di sisi klien bisa diakali penyerang
 * yang cukup niat (mis. Magisk + DenyList). Gunanya menaikkan biaya serangan
 * dan menghentikan alat otomatis yang umum — bukan pengganti otorisasi di server.
 *
 * Dijalankan di thread latar: membaca /proc & sistem file bisa lambat.
 */
class KeamananPerangkatChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "nara/keamanan_perangkat")
    private val utama = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "periksa" -> Thread {
                    val hasil = try {
                        periksa()
                    } catch (e: Throwable) {
                        mapOf("galat" to (e.message ?: e.javaClass.simpleName))
                    }
                    utama.post { result.success(hasil) }
                }.start()
                "aturLayarAman" -> {
                    // FLAG_SECURE: layar tak bisa di-screenshot/direkam dan
                    // tampil kosong di daftar aplikasi terbaru.
                    val aktif = call.argument<Boolean>("aktif") ?: false
                    activity.runOnUiThread {
                        if (aktif) {
                            activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    private fun periksa(): Map<String, Any?> {
        val alasanRoot = mutableListOf<String>()
        val alasanHook = mutableListOf<String>()
        val alasanEmulator = mutableListOf<String>()
        val sinyalLemah = mutableListOf<String>()

        // ── Root ────────────────────────────────────────────────────────
        val jalurSu = listOf(
            "/system/bin/su", "/system/xbin/su", "/sbin/su", "/system/su",
            "/system/sbin/su", "/vendor/bin/su", "/su/bin/su", "/data/local/su",
            "/data/local/bin/su", "/data/local/xbin/su", "/cache/su", "/dev/su",
            "/system/bin/.ext/.su", "/system/usr/we-need-root/su-backup",
        )
        jalurSu.filter { File(it).exists() }.forEach { alasanRoot += "su:$it" }
        listOf("/sbin/.magisk", "/data/adb/magisk", "/data/adb/ksu", "/cache/.disable_magisk")
            .filter { File(it).exists() }
            .forEach { alasanRoot += "magisk:$it" }
        val paketRoot = listOf(
            "com.topjohnwu.magisk", "eu.chainfire.supersu", "com.noshufou.android.su",
            "com.koushikdutta.superuser", "com.thirdparty.superuser", "com.kingroot.kinguser",
            "com.kingouser.com", "me.weishu.kernelsu", "com.yellowes.su",
        )
        paketRoot.filter { terpasang(it) }.forEach { alasanRoot += "paket:$it" }
        // Sinyal lemah: banyak perangkat POS murah memakai build test-keys /
        // debuggable dari pabriknya — dicatat, tidak memblokir.
        if (Build.TAGS?.contains("test-keys") == true) sinyalLemah += "build:test-keys"
        if (properti("ro.debuggable") == "1") sinyalLemah += "prop:ro.debuggable=1"
        if (properti("ro.secure") == "0") sinyalLemah += "prop:ro.secure=0"

        // ── Debugger ────────────────────────────────────────────────────
        val debugger = Debug.isDebuggerConnected() || Debug.waitingForDebugger()
        // APK rilis yang tiba-tiba "debuggable" = sudah dibongkar & dirakit ulang.
        val dapatDidebug = (activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

        // ── Hooking / instrumentasi (Frida, Xposed/LSPosed, Substrate) ─────
        val penandaHook = listOf("frida", "gadget", "xposed", "lspd", "lsposed", "edxp", "substrate")
        try {
            File("/proc/self/maps").useLines { baris ->
                baris.forEach { b ->
                    val kecil = b.lowercase()
                    penandaHook.firstOrNull { kecil.contains(it) }?.let { alasanHook += "maps:$it" }
                }
            }
        } catch (_: Throwable) {
            // Tak bisa dibaca — lewati.
        }
        // Thread khas agen Frida di dalam proses.
        try {
            File("/proc/self/task").listFiles()?.forEach { t ->
                val nama = try { File(t, "comm").readText().trim() } catch (_: Throwable) { "" }
                if (nama == "gum-js-loop" || nama == "pool-frida") {
                    alasanHook += "thread:$nama"
                }
            }
        } catch (_: Throwable) {
        }
        for (kelas in listOf("de.robv.android.xposed.XposedBridge", "de.robv.android.xposed.XC_MethodHook")) {
            try {
                Class.forName(kelas)
                alasanHook += "kelas:$kelas"
            } catch (_: Throwable) {
            }
        }

        // ── Emulator ────────────────────────────────────────────────────
        val fp = Build.FINGERPRINT ?: ""
        val model = Build.MODEL ?: ""
        val hw = Build.HARDWARE ?: ""
        val produk = Build.PRODUCT ?: ""
        if (fp.startsWith("generic") || fp.startsWith("unknown") || fp.contains("emulator")) alasanEmulator += "fingerprint"
        if (model.contains("google_sdk") || model.contains("Emulator") || model.contains("Android SDK built for")) alasanEmulator += "model"
        if (Build.MANUFACTURER?.contains("Genymotion") == true) alasanEmulator += "genymotion"
        if (hw == "goldfish" || hw == "ranchu" || hw.contains("vbox")) alasanEmulator += "hardware:$hw"
        if (produk.startsWith("sdk") || produk.contains("emulator") || produk.contains("simulator") || produk.contains("vbox")) alasanEmulator += "produk:$produk"
        if (properti("ro.kernel.qemu") == "1") alasanEmulator += "qemu"

        return mapOf(
            "root" to alasanRoot.distinct(),
            "hook" to alasanHook.distinct(),
            "emulator" to alasanEmulator.distinct(),
            "lemah" to sinyalLemah,
            "debugger" to debugger,
            "dapat_didebug" to dapatDidebug,
            "sertifikat_sha256" to sertifikatSha256(),
            "pemasang" to pemasang(),
        )
    }

    private fun terpasang(paket: String): Boolean = try {
        activity.packageManager.getPackageInfo(paket, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    } catch (_: Throwable) {
        false
    }

    /** android.os.SystemProperties (API tersembunyi) lewat refleksi. */
    private fun properti(nama: String): String? = try {
        val kelas = Class.forName("android.os.SystemProperties")
        kelas.getMethod("get", String::class.java).invoke(null, nama) as? String
    } catch (_: Throwable) {
        null
    }

    /**
     * SHA-256 sertifikat penanda tangan APK (heks huruf besar, tanpa titik dua).
     * APK yang dibongkar lalu ditandatangani ulang orang lain menghasilkan nilai
     * berbeda — dibandingkan di Dart dengan nilai rilis resmi.
     */
    @Suppress("DEPRECATION")
    private fun sertifikatSha256(): String? = try {
        val pm = activity.packageManager
        val tanda = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val info = pm.getPackageInfo(activity.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            val si = info.signingInfo
            if (si == null) {
                null
            } else if (si.hasMultipleSigners()) {
                si.apkContentsSigners
            } else {
                // Riwayat rotasi kunci: penanda tangan AKTIF ada di urutan terakhir.
                si.signingCertificateHistory?.reversedArray()
            }
        } else {
            pm.getPackageInfo(activity.packageName, PackageManager.GET_SIGNATURES).signatures
        }
        tanda?.firstOrNull()?.let { s ->
            MessageDigest.getInstance("SHA-256").digest(s.toByteArray())
                .joinToString("") { "%02X".format(it) }
        }
    } catch (_: Throwable) {
        null
    }

    @Suppress("DEPRECATION")
    private fun pemasang(): String? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.packageManager.getInstallSourceInfo(activity.packageName).installingPackageName
        } else {
            activity.packageManager.getInstallerPackageName(activity.packageName)
        }
    } catch (_: Throwable) {
        null
    }
}
