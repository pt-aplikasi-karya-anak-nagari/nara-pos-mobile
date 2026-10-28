package com.example.nara_pos_mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileNotFoundException
import java.util.concurrent.Executors

/**
 * Akses ke folder yang dipilih pengguna (Storage Access Framework) untuk data
 * offline.
 *
 * KENAPA SAF, BUKAN FILE BIASA
 *
 * File di folder milik aplikasi ikut terhapus saat aplikasi di-uninstall.
 * File di folder bersama (mis. Documents) memang tetap ada, tapi sejak
 * Android 11 aplikasi yang di-install ulang tidak lagi boleh membacanya.
 * Folder yang dipilih pengguna lewat pemilih sistem bisa dibaca lagi setelah
 * install ulang: pengguna cukup memilih folder yang sama.
 *
 * Semua operasi file jalan berurutan di SATU thread latar, supaya penulisan
 * produk demi produk tidak saling tindih dan cache ID dokumen di bawah tidak
 * perlu dikunci.
 */
class FolderOfflineChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "nara/folder_offline")
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null

    // "<tree>|<idInduk>|<nama>" → ID dokumen folder.
    private val dirCache = HashMap<String, String>()

    // "<tree>|<idFolder>" → (nama file → ID dokumen). Daftar isi folder dibaca
    // sekali; tanpa ini, setiap tulis harus men-query seluruh isi folder.
    private val fileCache = HashMap<String, HashMap<String, String>>()

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFolder" -> pickFolder(result)
            "hasAccess" -> result.success(hasAccess(call.argument<String>("uri") ?: ""))
            "folderName" -> background(result) { folderName(Uri.parse(call.arg("uri"))) }
            "writeFile" -> background(result) {
                writeFile(
                    Uri.parse(call.arg("uri")),
                    call.argument<List<String>>("dir") ?: emptyList(),
                    call.arg("name"),
                    call.arg("content"),
                )
                null
            }
            "readAll" -> background(result) {
                readAll(
                    Uri.parse(call.arg("uri")),
                    call.argument<List<String>>("dir") ?: emptyList(),
                )
            }
            "listNames" -> background(result) {
                listNames(
                    Uri.parse(call.arg("uri")),
                    call.argument<List<String>>("dir") ?: emptyList(),
                )
            }
            "deleteFile" -> background(result) {
                deleteFile(
                    Uri.parse(call.arg("uri")),
                    call.argument<List<String>>("dir") ?: emptyList(),
                    call.arg("name"),
                )
            }
            else -> result.notImplemented()
        }
    }

    // ── Pilih folder ──────────────────────────────────────────────────────────

    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("BUSY", "Pemilih folder sedang terbuka.", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, REQUEST_PICK)
        } catch (e: Exception) {
            pendingPick = null
            result.error("NO_PICKER", "Pemilih folder tidak tersedia di perangkat ini.", null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        try {
            // Izin bertahan walau aplikasi ditutup/HP restart. Setelah install
            // ulang izin ini hilang — pengguna memilih folder yang sama lagi.
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
            result.success(uri.toString())
        } catch (e: SecurityException) {
            result.error("NO_ACCESS", "Folder ini tidak bisa dipakai. Pilih folder lain.", null)
        }
        return true
    }

    private fun hasAccess(uri: String): Boolean {
        if (uri.isEmpty()) return false
        return activity.contentResolver.persistedUriPermissions.any {
            it.uri.toString() == uri && it.isReadPermission && it.isWritePermission
        }
    }

    private fun folderName(tree: Uri): String? {
        val docUri = DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        activity.contentResolver.query(
            docUri,
            arrayOf(Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { c -> if (c.moveToFirst()) return c.getString(0) }
        return null
    }

    // ── Baca & tulis ──────────────────────────────────────────────────────────

    private fun writeFile(tree: Uri, dir: List<String>, name: String, content: String) {
        val dirId = resolveDir(tree, dir, create = true)!!
        val bytes = content.toByteArray(Charsets.UTF_8)
        val files = files(tree, dirId)
        val existing = files[name]
        if (existing != null) {
            try {
                write(DocumentsContract.buildDocumentUriUsingTree(tree, existing), bytes)
                return
            } catch (e: FileNotFoundException) {
                // File dihapus dari luar aplikasi: lupakan, buat ulang di bawah.
                files.remove(name)
            }
        }
        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, dirId)
        val created = DocumentsContract.createDocument(
            activity.contentResolver,
            parent,
            "application/json",
            name,
        ) ?: throw IllegalStateException("Gagal membuat file $name")
        files[name] = DocumentsContract.getDocumentId(created)
        write(created, bytes)
    }

    private fun write(uri: Uri, bytes: ByteArray) {
        // "wt": timpa dan potong, supaya isi lama yang lebih panjang tidak
        // tersisa di ekor file.
        val out = activity.contentResolver.openOutputStream(uri, "wt")
            ?: throw FileNotFoundException(uri.toString())
        out.use { it.write(bytes) }
    }

    private fun readAll(tree: Uri, dir: List<String>): Map<String, String> {
        val dirId = resolveDir(tree, dir, create = false) ?: return emptyMap()
        val hasil = HashMap<String, String>()
        for ((name, id) in files(tree, dirId, refresh = true)) {
            if (!name.endsWith(".json")) continue
            try {
                val uri = DocumentsContract.buildDocumentUriUsingTree(tree, id)
                activity.contentResolver.openInputStream(uri)?.use {
                    hasil[name] = it.readBytes().toString(Charsets.UTF_8)
                }
            } catch (e: Exception) {
                // Satu file rusak/terkunci tidak boleh menggagalkan yang lain.
            }
        }
        return hasil
    }

    private fun listNames(tree: Uri, dir: List<String>): List<String> {
        val dirId = resolveDir(tree, dir, create = false) ?: return emptyList()
        return files(tree, dirId, refresh = true).keys.toList()
    }

    private fun deleteFile(tree: Uri, dir: List<String>, name: String): Boolean {
        val dirId = resolveDir(tree, dir, create = false) ?: return false
        val files = files(tree, dirId)
        val id = files[name] ?: return false
        files.remove(name)
        return try {
            DocumentsContract.deleteDocument(
                activity.contentResolver,
                DocumentsContract.buildDocumentUriUsingTree(tree, id),
            )
        } catch (e: FileNotFoundException) {
            false
        }
    }

    // ── Folder & cache ID dokumen ─────────────────────────────────────────────

    private fun resolveDir(tree: Uri, dir: List<String>, create: Boolean): String? {
        var parent = DocumentsContract.getTreeDocumentId(tree)
        for (segment in dir) {
            val key = "$tree|$parent|$segment"
            val cached = dirCache[key]
            if (cached != null) {
                parent = cached
                continue
            }
            val found = children(tree, parent).firstOrNull {
                it.name == segment && it.mime == Document.MIME_TYPE_DIR
            }?.id
            val id = found ?: if (create) {
                val made = DocumentsContract.createDocument(
                    activity.contentResolver,
                    DocumentsContract.buildDocumentUriUsingTree(tree, parent),
                    Document.MIME_TYPE_DIR,
                    segment,
                ) ?: throw IllegalStateException("Gagal membuat folder $segment")
                DocumentsContract.getDocumentId(made)
            } else {
                return null
            }
            dirCache[key] = id
            parent = id
        }
        return parent
    }

    private fun files(tree: Uri, dirId: String, refresh: Boolean = false): HashMap<String, String> {
        val key = "$tree|$dirId"
        if (!refresh) fileCache[key]?.let { return it }
        val map = HashMap<String, String>()
        for (c in children(tree, dirId)) {
            if (c.mime != Document.MIME_TYPE_DIR) map[c.name] = c.id
        }
        fileCache[key] = map
        return map
    }

    private data class Child(val id: String, val name: String, val mime: String)

    private fun children(tree: Uri, parentId: String): List<Child> {
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
        val list = ArrayList<Child>()
        activity.contentResolver.query(
            uri,
            arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE),
            null,
            null,
            null,
        )?.use { c ->
            while (c.moveToNext()) {
                list.add(Child(c.getString(0), c.getString(1) ?: "", c.getString(2) ?: ""))
            }
        }
        return list
    }

    // ── Utilitas ──────────────────────────────────────────────────────────────

    private fun background(result: MethodChannel.Result, kerja: () -> Any?) {
        io.execute {
            try {
                val nilai = kerja()
                main.post { result.success(nilai) }
            } catch (e: SecurityException) {
                // Izin folder dicabut atau folder sudah tidak ada.
                dirCache.clear()
                fileCache.clear()
                main.post { result.error("NO_ACCESS", "Akses ke folder hilang. Pilih folder lagi.", null) }
            } catch (e: Exception) {
                dirCache.clear()
                fileCache.clear()
                main.post { result.error("FOLDER_ERROR", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun MethodCall.arg(name: String): String =
        argument<String>(name) ?: throw IllegalArgumentException("Argumen '$name' kosong")

    companion object {
        private const val REQUEST_PICK = 7311
    }
}
