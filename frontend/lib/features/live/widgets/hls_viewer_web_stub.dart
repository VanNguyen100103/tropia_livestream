// Stub for non-web platforms — HlsViewer never instantiates HlsViewerWeb
// off-web, but conditional imports still need a symbol to resolve to.

import 'package:flutter/material.dart';

class HlsViewerWeb extends StatelessWidget {
  final String hlsUrl;
  final BoxFit fit;
  final bool autoplay;
  final bool muted;
  final bool loop;
  final String? posterUrl;
  final VoidCallback? onReady;
  final VoidCallback? onError;
  final Future<void> Function()? onRetry;

  const HlsViewerWeb({
    super.key,
    required this.hlsUrl,
    required this.fit,
    required this.autoplay,
    this.muted = false,
    this.loop = false,
    this.posterUrl,
    this.onReady,
    this.onError,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
