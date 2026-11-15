package com.example.nara_pos_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var folderOffline: FolderOfflineChannel? = null
    private var jamSistem: JamSistemChannel? = null
    private var keamanan: KeamananPerangkatChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        folderOffline = FolderOfflineChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        jamSistem = JamSistemChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        keamanan = KeamananPerangkatChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        folderOffline?.dispose()
        folderOffline = null
        jamSistem?.dispose()
        jamSistem = null
        keamanan?.dispose()
        keamanan = null
        super.onDestroy()
    }
}
