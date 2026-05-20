// Flutter Web — dùng livekit_client native Web support (không cần JS bridge)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:tropia/core/utils/logger.dart';

const _tag = 'LiveKitWebViewer';

class LiveKitWebViewer extends StatefulWidget {
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
  State<LiveKitWebViewer> createState() => _LiveKitWebViewerState();
}

class _LiveKitWebViewerState extends State<LiveKitWebViewer> {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  VideoTrack? _hostVideoTrack;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    final room = Room();
    _listener = room.createListener();

    _listener!
      ..on<TrackSubscribedEvent>((e) {
        if (e.track is VideoTrack) {
          setState(() => _hostVideoTrack = e.track as VideoTrack);
          AppLogger.logInfo(_tag, 'Video track subscribed');
          widget.onVideoReady?.call();
        }
      })
      ..on<TrackUnsubscribedEvent>((e) {
        if (e.track is VideoTrack) {
          setState(() => _hostVideoTrack = null);
          AppLogger.logInfo(_tag, 'Video track unsubscribed');
          widget.onVideoStopped?.call();
        }
      });

    await room.connect(
      widget.wsUrl,
      widget.token,
      roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
    );

    // Host đã publish trước khi viewer join — subscribe ngay
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.videoTrackPublications) {
        if (pub.subscribed && pub.track != null) {
          setState(() => _hostVideoTrack = pub.track as VideoTrack);
          widget.onVideoReady?.call();
        }
      }
    }

    _room = room;
    AppLogger.logInfo(_tag, 'Web viewer connected: ${room.name}');
  }

  @override
  void dispose() {
    _listener?.dispose();
    _room?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hostVideoTrack == null) {
      return const ColoredBox(color: Colors.black);
    }
    return VideoTrackRenderer(_hostVideoTrack!);
  }
}
