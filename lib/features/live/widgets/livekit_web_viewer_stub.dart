import 'package:flutter/material.dart';

/// Stub cho non-web platforms — không bao giờ được render trên mobile.
class LiveKitWebViewer extends StatelessWidget {
  final String wsUrl;
  final String token;
  final VoidCallback? onVideoReady;
  final VoidCallback? onVideoStopped;

  const LiveKitWebViewer({
    super.key,
    required this.wsUrl,
    required this.token,
    this.onVideoReady,
    this.onVideoStopped,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
