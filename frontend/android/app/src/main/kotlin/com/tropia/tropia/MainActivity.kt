package com.tropia.tropia

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // MethodChannel bridge for the foreground service. Flutter calls
    // `tropia/live_stream`.{startLive,stopLive} around the apivideo
    // publish lifecycle so the OS keeps the process alive while the
    // host's screen is locked or the app is backgrounded.
    private val channelName = "tropia/live_stream"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startLive" -> {
                        val title = call.argument<String>("title") ?: "Livestream Tropia"
                        LiveStreamForegroundService.start(applicationContext, title)
                        result.success(true)
                    }
                    "stopLive" -> {
                        LiveStreamForegroundService.stop(applicationContext)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
