import 'package:flutter/material.dart';

/// Stub cho non-web platforms — không bao giờ được render trên mobile.
class AgoraWebViewer extends StatelessWidget {
  final String appId;
  final String channel;
  final String token;
  final int uid;
  final VoidCallback? onVideoReady;
  final VoidCallback? onVideoStopped;

  const AgoraWebViewer({
    super.key,
    required this.appId,
    required this.channel,
    required this.token,
    required this.uid,
    this.onVideoReady,
    this.onVideoStopped,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
