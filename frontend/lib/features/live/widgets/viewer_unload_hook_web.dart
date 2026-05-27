// Web-only: ensure `/leave` fires even when the user closes the tab or
// hits F5 instead of using the in-app back button — both bypass Flutter's
// State.dispose, leaving the viewer row in live_viewers and the
// viewer_count stuck at 1 (the bug the host saw as "đã out mà vẫn 1").
//
// fetch(..., {keepalive: true}) is the modern replacement for
// navigator.sendBeacon when you need to send an Authorization header,
// which sendBeacon doesn't support. The browser will let the request
// outlive the page for up to 64KB / a few seconds — plenty for a one-line
// POST. Supported in Chrome 66+, Firefox 78+, Safari 13+ (covers
// effectively all 2026 traffic).

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

class ViewerUnloadHook {
  final String url;
  final String? bearerToken;
  StreamSubscription<web.Event>? _sub;
  bool _fired = false;

  ViewerUnloadHook({required this.url, required this.bearerToken});

  void install() {
    // `pagehide` fires in more cases than `beforeunload` (mobile Safari
    // doesn't reliably fire beforeunload). Listen to both and dedupe.
    final handler = ((web.Event _) {
      if (_fired) return;
      _fired = true;
      _send();
    }).toJS;
    web.window.addEventListener('pagehide', handler);
    web.window.addEventListener('beforeunload', handler);
  }

  void _send() {
    final headers = {
      'Content-Type': 'application/json',
      if (bearerToken != null && bearerToken!.isNotEmpty)
        'Authorization': 'Bearer $bearerToken',
    }.jsify() as JSObject;
    final init = web.RequestInit(
      method: 'POST',
      keepalive: true,
      headers: headers,
      body: ''.toJS,
    );
    try {
      web.window.fetch(url.toJS, init);
    } catch (_) {/* unload — nothing we can do anyway */}
  }

  void dispose() {
    _sub?.cancel();
    // The actual JS listeners reference the .toJS closure we lost on
    // install — they'll fire at most once due to `_fired`. Letting them
    // be garbage-collected on page navigation is fine.
  }
}

/// Public constructor used by [LiveStreamScreen]. Returns a no-op object
/// on non-web platforms (see the stub).
ViewerUnloadHook? installViewerUnloadHook({
  required String url,
  required String? bearerToken,
}) {
  final hook = ViewerUnloadHook(url: url, bearerToken: bearerToken);
  hook.install();
  return hook;
}
