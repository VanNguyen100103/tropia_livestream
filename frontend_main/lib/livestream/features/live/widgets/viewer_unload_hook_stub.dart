// Stub used on non-web platforms — Flutter's State.dispose fires reliably
// on mobile/desktop, so we don't need a beforeunload-style hook there.

class ViewerUnloadHook {
  void dispose() {}
}

ViewerUnloadHook? installViewerUnloadHook({
  required String url,
  required String? bearerToken,
}) =>
    null;
