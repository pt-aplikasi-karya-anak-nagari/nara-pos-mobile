package com.example.nara_pos_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var folderOffline: FolderOfflineChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        folderOffline = FolderOfflineChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        folderOffline?.dispose()
        folderOffline = null
        super.onDestroy()
    }
}
