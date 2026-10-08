package io.alanteh.driver

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Notification channels the Dart side defines; see
        // lib/notifications/trip_offer_channel.dart.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.alanteh.driver/notification_channels",
        ).setMethodCallHandler { call, result ->
            if (call.method != "createChannel") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val id = call.argument<String>("id")
            val name = call.argument<String>("name")
            if (id == null || name == null) {
                result.error("bad_arguments", "id and name are required", null)
                return@setMethodCallHandler
            }
            // Channels exist from Android 8; before that a push needs none.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val importance =
                    if (call.argument<String>("importance") == "high") {
                        NotificationManager.IMPORTANCE_HIGH
                    } else {
                        NotificationManager.IMPORTANCE_DEFAULT
                    }
                val channel = NotificationChannel(id, name, importance)
                channel.description = call.argument<String>("description")
                getSystemService(NotificationManager::class.java)
                    .createNotificationChannel(channel)
            }
            result.success(null)
        }
    }
}
