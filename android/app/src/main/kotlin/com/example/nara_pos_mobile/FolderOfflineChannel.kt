package com.example.nara_pos_mobile

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Penyimpanan cadangan data offline (produk, add-on, transaksi) yang:
 *
 *   - OTOMATIS: tanpa pengguna memilih folder;
 *   - TERSEMBUNYI: lokasinya tak pernah ditampilkan aplikasi, nama foldernya
 *     diawali titik dan berisi .nomedia;
 *   - TERENKRIPSI: isi file AES-GCM dengan kunci yang terikat ke perangkat ini,
 *     jadi tak bisa dibaca atau diubah dari luar aplikasi — file yang diubah
 *     gagal didekripsi dan diabaikan;
 *   - TETAP ADA setelah aplikasi di-uninstall, dan terbaca lagi setelah
 *     install ulang.
 *
 * # KENAPA BUTUH IZIN "AKSES SEMUA FILE"
 *
 * Folder milik aplikasi ikut terhapus saat uninstall. Folder bersama tidak,
 * tapi sejak Android 11 aplikasi yang di-install ulang tak lagi boleh membaca
 * file lamanya sendiri di sana. Hanya dengan MANAGE_EXTERNAL_STORAGE (Android
 * 11+) atau WRITE_EXTERNAL_STORAGE (Android 10 ke bawah) keduanya terpenuhi.
 * Izin diminta di gerbang izin saat aplikasi pertama dibuka.
 *
 * # KUNCI ENKRIPSI
 *
 * SHA-256 dari rahasia aplikasi + ANDROID_ID. Sejak Android 8, ANDROID_ID
 * tetap sama setelah install ulang selama aplikasinya ditandatangani kunci
 * yang sama — jadi cadangan terbaca lagi setelah install ulang, tapi tidak di
 * perangkat lain.
 */
class FolderOfflineChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "nara/folder_offline")
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val acak = SecureRandom()
    private val kunci: SecretKeySpec by lazy { buatKunci() }

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasAccess" -> result.success(punyaAkses())
            "writeFile" -> background(result) {
                tulis(call.dir(), call.arg("name"), call.arg("content"))
                null
            }
            "readAll" -> background(result) { bacaSemua(call.dir()) }
            "listNames" -> background(result) { daftarNama(call.dir()) }
            "deleteFile" -> background(result) { hapus(call.dir(), call.arg("name")) }
            else -> result.notImplemented()
        }
    }

    // ── Akses ─────────────────────────────────────────────────────────────────

    private fun punyaAkses(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }

    private fun akar(): File {
        if (!punyaAkses()) throw SecurityException("Izin penyimpanan cadangan belum diberikan")
        @Suppress("DEPRECATION")
        val akar = File(Environment.getExternalStorageDirectory(), NAMA_AKAR)
        if (!akar.exists() && !akar.mkdirs()) {
            throw IllegalStateException("Penyimpanan cadangan tidak bisa dibuat")
        }
        // Jangan sampai isinya muncul di galeri / pemindai media.
        File(akar, ".nomedia").let { if (!it.exists()) it.createNewFile() }
        return akar
    }

    private fun folder(segmen: List<String>, buat: Boolean): File? {
        var f = akar()
        for (s in segmen) {
            f = File(f, aman(s))
        }
        if (!f.exists()) {
            if (!buat) return null
            if (!f.mkdirs()) throw IllegalStateException("Folder cadangan tidak bisa dibuat")
        }
        return f
    }

    // ── Baca & tulis ──────────────────────────────────────────────────────────

    private fun tulis(dir: List<String>, nama: String, isi: String) {
        val f = folder(dir, buat = true)!!
        val tujuan = File(f, namaDisimpan(nama))
        // Tulis ke file sementara lalu ganti nama: listrik padam di tengah
        // penulisan tidak meninggalkan file setengah jadi yang menimpa salinan
        // yang masih utuh.
        val sementara = File(f, tujuan.name + ".tmp")
        sementara.writeBytes(enkripsi(isi.toByteArray(Charsets.UTF_8)))
        if (!sementara.renameTo(tujuan)) {
            tujuan.delete()
            if (!sementara.renameTo(tujuan)) {
                sementara.delete()
                throw IllegalStateException("Gagal menyimpan $nama")
            }
        }
    }

    private fun bacaSemua(dir: List<String>): Map<String, String> {
        val f = folder(dir, buat = false) ?: return emptyMap()
        val hasil = HashMap<String, String>()
        for (file in f.listFiles().orEmpty()) {
            if (!file.isFile || !file.name.endsWith(EKSTENSI)) continue
            try {
                hasil[namaAsli(file.name)] = String(dekripsi(file.readBytes()), Charsets.UTF_8)
            } catch (e: Exception) {
                // Rusak atau diubah dari luar aplikasi: diabaikan.
            }
        }
        return hasil
    }

    private fun daftarNama(dir: List<String>): List<String> {
        val f = folder(dir, buat = false) ?: return emptyList()
        return f.listFiles().orEmpty()
            .filter { it.isFile && it.name.endsWith(EKSTENSI) }
            .map { namaAsli(it.name) }
    }

    private fun hapus(dir: List<String>, nama: String): Boolean {
        val f = folder(dir, buat = false) ?: return false
        return File(f, namaDisimpan(nama)).delete()
    }

    // Dart memakai nama "<id>.json"; di disk disimpan "<id>.dat" supaya tak
    // tampak sebagai data yang bisa dibuka.
    private fun namaDisimpan(nama: String) = aman(nama.removeSuffix(".json")) + EKSTENSI
    private fun namaAsli(disimpan: String) = disimpan.removeSuffix(EKSTENSI) + ".json"

    // ── Enkripsi ──────────────────────────────────────────────────────────────

    private fun enkripsi(data: ByteArray): ByteArray {
        val iv = ByteArray(12).also { acak.nextBytes(it) }
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, kunci, GCMParameterSpec(128, iv))
        return MAGIC + iv + c.doFinal(data)
    }

    private fun dekripsi(data: ByteArray): ByteArray {
        require(data.size > MAGIC.size + 12 && data.copyOfRange(0, MAGIC.size).contentEquals(MAGIC))
        val iv = data.copyOfRange(MAGIC.size, MAGIC.size + 12)
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, kunci, GCMParameterSpec(128, iv))
        return c.doFinal(data, MAGIC.size + 12, data.size - MAGIC.size - 12)
    }

    @SuppressLint("HardwareIds")
    private fun buatKunci(): SecretKeySpec {
        val idPerangkat = Settings.Secure.getString(
            activity.contentResolver,
            Settings.Secure.ANDROID_ID,
        ) ?: ""
        val bahan = (RAHASIA + "|" + idPerangkat).toByteArray(Charsets.UTF_8)
        return SecretKeySpec(MessageDigest.getInstance("SHA-256").digest(bahan), "AES")
    }

    // ── Utilitas ──────────────────────────────────────────────────────────────

    private fun background(result: MethodChannel.Result, kerja: () -> Any?) {
        io.execute {
            try {
                val nilai = kerja()
                main.post { result.success(nilai) }
            } catch (e: SecurityException) {
                main.post { result.error("NO_ACCESS", "Izin penyimpanan cadangan belum diberikan.", null) }
            } catch (e: Exception) {
                main.post { result.error("FOLDER_ERROR", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun MethodCall.arg(name: String): String =
        argument<String>(name) ?: throw IllegalArgumentException("Argumen '$name' kosong")

    private fun MethodCall.dir(): List<String> = argument<List<String>>("dir") ?: emptyList()

    /** Segmen path aman: tak bisa naik folder atau keluar dari akar cadangan. */
    private fun aman(s: String): String = s.replace(Regex("[^A-Za-z0-9_.-]"), "_").let {
        if (it == "." || it == "..") "_" else it
    }

    companion object {
        private const val NAMA_AKAR = ".np-sys"
        private const val EKSTENSI = ".dat"
        private val MAGIC = byteArrayOf(0x4E, 0x31) // "N1" — versi format file
        private const val RAHASIA = "nara-pos/cadangan-offline/v1/7c1e9b4a2f"
    }
}
