// Flutter ↔ Android MethodChannel bridge for the RTMP foreground
// service. Without this, locking the phone or backgrounding the app
// for more than ~5 min kills the Flutter process → apivideo's camera
// + RTMP socket die → SRS fires on_unpublish → buyers see the stream
// end even though the host hasn't tapped "Kết thúc Live".
//
// The service itself is a no-op on iOS / web / desktop — only Android
// needs explicit foreground service plumbing. iOS handles long-running
// RTMP capture via the existing background mode entitlements
// `audio` + `voip` that apivideo sets up.

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';

class LiveForegroundService {
  static const _channel = MethodChannel('tropia/live_stream');

  /// Anchor the process so the OS won't kill it while RTMP is live.
  /// Safe to call repeatedly — Android's startForeground is idempotent
  /// when the service is already running.
  static Future<void> start({required String title}) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('startLive', {'title': title});
    } catch (_) {
      // MissingPluginException can happen on hot-restart before the
      // engine is fully wired. Better to let the stream proceed
      // without the service anchor than crash the publish flow.
    }
  }

  static Future<void> stop() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('stopLive');
    } catch (_) {}
  }

  static bool get _supported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android;
  }
}
