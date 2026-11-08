package id.nara.pos

import android.content.Context
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Jam sistem yang TIDAK bisa diubah pengguna, untuk mendeteksi jam perangkat
 * yang dimundurkan/dimajukan saat offline (lib/core/offline/jam_terpercaya.dart).
 *
 *  uptime_ms  SystemClock.elapsedRealtime(): milidetik sejak boot, termasuk
 *             saat layar mati/tidur. Tak terpengaruh pengaturan tanggal & jam.
 *  boot       Settings.Global.BOOT_COUNT (API 24+): naik setiap perangkat
 *             dinyalakan ulang — uptime dari boot berbeda tak bisa dibandingkan.
 */
class JamSistemChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "nara/jam_sistem")

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "baca" -> {
                    val boot: Int? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        try {
                            Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT)
                        } catch (e: Exception) {
                            null
                        }
                    } else {
                        null
                    }
                    result.success(
                        mapOf(
                            "uptime_ms" to SystemClock.elapsedRealtime(),
                            "boot" to boot,
                        ),
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
