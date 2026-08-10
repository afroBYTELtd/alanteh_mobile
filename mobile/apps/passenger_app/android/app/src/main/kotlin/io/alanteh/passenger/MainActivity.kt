package io.alanteh.passenger

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "io.alanteh.passenger/settings"
        private const val PREFERENCES = "alanteh_passenger_settings"
        private val LEGAL_URLS = setOf(
            "https://alanteh.io/privacy",
            "https://alanteh.io/terms",
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val preferences = getSharedPreferences(PREFERENCES, MODE_PRIVATE)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "readPreference" -> {
                    val key = call.argument<String>("key")
                    if (key == null) {
                        result.error("invalid_preference", "Preference key is required.", null)
                    } else {
                        result.success(preferences.getBoolean(key, true))
                    }
                }

                "writePreference" -> {
                    val key = call.argument<String>("key")
                    val value = call.argument<Boolean>("value")
                    if (key == null || value == null) {
                        result.error("invalid_preference", "Preference key and value are required.", null)
                    } else {
                        preferences.edit().putBoolean(key, value).apply()
                        result.success(null)
                    }
                }

                "openInAppBrowser" -> {
                    val url = call.argument<String>("url")
                    if (url == null || !LEGAL_URLS.contains(url)) {
                        result.error("invalid_url", "Unsupported legal URL.", null)
                    } else {
                        startActivity(
                            Intent(this, PassengerLegalWebViewActivity::class.java)
                                .putExtra(PassengerLegalWebViewActivity.EXTRA_URL, url),
                        )
                        result.success(null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}

class PassengerLegalWebViewActivity : Activity() {
    companion object {
        const val EXTRA_URL = "legal_url"
        private val LEGAL_URLS = setOf(
            "https://alanteh.io/privacy",
            "https://alanteh.io/terms",
        )
    }

    private lateinit var webView: WebView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val url = intent.getStringExtra(EXTRA_URL)
        if (url == null || !LEGAL_URLS.contains(url)) {
            finish()
            return
        }

        title = "ALANTEH"
        webView = WebView(this).apply {
            webViewClient = WebViewClient()
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            loadUrl(url)
        }
        setContentView(webView)
    }

    override fun onBackPressed() {
        if (::webView.isInitialized && webView.canGoBack()) {
            webView.goBack()
        } else {
            super.onBackPressed()
        }
    }

    override fun onDestroy() {
        if (::webView.isInitialized) {
            webView.destroy()
        }
        super.onDestroy()
    }
}
