package com.example.nara_pos_mobile

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var folderOffline: FolderOfflineChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        folderOffline = FolderOfflineChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    @Deprecated("Dipakai untuk hasil pemilih folder (ACTION_OPEN_DOCUMENT_TREE).")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (folderOffline?.onActivityResult(requestCode, resultCode, data) == true) return
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        folderOffline?.dispose()
        folderOffline = null
        super.onDestroy()
    }
}
