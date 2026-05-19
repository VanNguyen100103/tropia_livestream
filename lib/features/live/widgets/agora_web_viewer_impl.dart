// Flutter Web only — dùng Agora JS SDK qua dart:js
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;
import 'dart:async';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class AgoraWebViewer extends StatefulWidget {
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
  State<AgoraWebViewer> createState() => _AgoraWebViewerState();
}

class _AgoraWebViewerState extends State<AgoraWebViewer> {
  late final String _viewType;
  late final String _containerId;
  static int _instanceCounter = 0;
  Timer? _readyTimer;

  @override
  void initState() {
    super.initState();
    _instanceCounter++;
    final id = _instanceCounter;
    _viewType    = 'agora-video-view-$id';
    _containerId = 'agora-flutter-container-$id';

    // Register the platform view factory
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) {
        // Create the container div that Agora will play video into
        final container = js.context.callMethod('eval', [
          '''(function() {
            var d = document.createElement('div');
            d.id = '$_containerId';
            d.style.cssText = 'width:100%;height:100%;background:#000;overflow:hidden;';
            return d;
          })()'''
        ]) as Object;
        // Register the container with the JS bridge
        js.context.callMethod('agoraSetContainer', [_containerId]);
        return container;
      },
    );

    // Join AFTER first frame so HtmlElementView is built and container div exists in DOM
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _joinChannel();
    });
  }

  void _joinChannel() {
    js.context.callMethod('agoraJoinViewer', [
      widget.appId,
      widget.channel,
      widget.token,
      widget.uid,
    ]);

    // Poll every 500ms until Agora injects a <video> into the container
    _readyTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final hasVideo = js.context.callMethod('eval', [
        '!!document.getElementById("$_containerId")?.querySelector("video")'
      ]);
      if (hasVideo == true) {
        _readyTimer?.cancel();
        if (mounted) widget.onVideoReady?.call();
      }
    });
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    js.context.callMethod('agoraLeaveViewer', []);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
