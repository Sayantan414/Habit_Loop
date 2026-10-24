package com.sayantan.habitloop.habit_loop

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var speech: SpeechChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        ReelsChannel.register(this, messenger)
        speech = SpeechChannel(this, messenger)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SpeechChannel.PERMISSION_REQUEST) {
            speech?.onPermissionResult(
                grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
            )
        }
    }

    override fun onDestroy() {
        speech?.dispose()
        speech = null
        super.onDestroy()
    }
}
