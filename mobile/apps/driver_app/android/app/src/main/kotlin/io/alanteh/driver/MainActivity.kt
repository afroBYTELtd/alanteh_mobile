package io.alanteh.driver

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
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
            when (call.method) {
                "channelState" -> {
                    result.success(channelState(call.argument<String>("id")))
                    return@setMethodCallHandler
                }
                "openChannelSettings" -> {
                    openChannelSettings(
                        call.argument<String>("id"),
                        call.argument<Boolean>("appLevel") == true,
                    )
                    result.success(true)
                    return@setMethodCallHandler
                }
                "createChannel" -> {}
                else -> {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
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

    // Whether app notifications are on, and the channel's importance (null
    // when it does not exist). "channels" is false before Android 8.
    private fun channelState(id: String?): Map<String, Any?> {
        val manager = getSystemService(NotificationManager::class.java)
        val appEnabled =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.N ||
                manager.areNotificationsEnabled()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return mapOf("appEnabled" to appEnabled, "channels" to false)
        }
        val importance = id?.let { manager.getNotificationChannel(it)?.importance }
        return mapOf(
            "appEnabled" to appEnabled,
            "channels" to true,
            "channelImportance" to importance,
        )
    }

    private fun openChannelSettings(id: String?, appLevel: Boolean) {
        val intent =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (appLevel || id == null) {
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                } else {
                    Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        .putExtra(Settings.EXTRA_CHANNEL_ID, id)
                }
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.fromParts("package", packageName, null))
            }
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
