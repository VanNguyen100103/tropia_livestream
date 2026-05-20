import 'dart:async';
import 'package:livekit_client/livekit_client.dart';
import 'package:tropia/core/services/auth_service.dart';
import 'package:tropia/core/utils/logger.dart';

const _tag = 'LiveKitService';

class LiveKitTokenResponse {
  final String token;
  final String wsUrl;
  final String room;
  final String identity;

  const LiveKitTokenResponse({
    required this.token,
    required this.wsUrl,
    required this.room,
    required this.identity,
  });
}

class LiveKitService {
  LiveKitService._();

  static get _dio => AuthService.instance.authorizedDio();

  // ── Token fetch ─────────────────────────────────────────────────────────────

  static Future<LiveKitTokenResponse> fetchToken({
    required String channelName,
    required bool isPublisher,
    int uid = 0,
  }) async {
    final res = await _dio.post('/api/token/livekit', data: {
      'channelName': channelName,
      'uid':         uid,
      'role':        isPublisher ? 'publisher' : 'subscriber',
    });
    return _parseToken(res.data as Map<String, dynamic>);
  }

  static Future<LiveKitTokenResponse> fetchTokenBySession({
    required String sessionId,
    required bool isPublisher,
    int uid = 0,
  }) async {
    final res = await _dio.post('/api/token/livekit', data: {
      'sessionId': sessionId,
      'uid':       uid,
      'role':      isPublisher ? 'publisher' : 'subscriber',
    });
    return _parseToken(res.data as Map<String, dynamic>);
  }

  static LiveKitTokenResponse _parseToken(Map<String, dynamic> d) =>
      LiveKitTokenResponse(
        token:    d['token']    as String,
        wsUrl:    d['wsUrl']    as String,
        room:     d['room']     as String,
        identity: d['identity'] as String,
      );

  // ── Room (Host / broadcaster) ───────────────────────────────────────────────

  static Future<Room> joinAsHost({
    required LiveKitTokenResponse tokenRes,
    void Function(RemoteParticipant)? onViewerJoined,
    void Function(RemoteParticipant)? onViewerLeft,
    void Function()? onTokenExpiring,
  }) async {
    final room = Room();

    room.addListener(() {
      // onParticipantConnected / onParticipantDisconnected
    });

    final listener = room.createListener();

    listener
      ..on<ParticipantConnectedEvent>((e) {
        AppLogger.logInfo(_tag, 'Viewer joined: ${e.participant.identity}');
        onViewerJoined?.call(e.participant);
      })
      ..on<ParticipantDisconnectedEvent>((e) {
        AppLogger.logInfo(_tag, 'Viewer left: ${e.participant.identity}');
        onViewerLeft?.call(e.participant);
      });

    await room.connect(
      tokenRes.wsUrl,
      tokenRes.token,
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast:       true,
      ),
    );

    // Publish camera + mic
    await room.localParticipant?.setCameraEnabled(true);
    await room.localParticipant?.setMicrophoneEnabled(true);

    // 720p 15fps
    await room.localParticipant?.setCameraEnabled(
      true,
      cameraCaptureOptions: const CameraCaptureOptions(
        params: VideoParametersPresets.h720_169,
      ),
    );

    AppLogger.logInfo(_tag, 'Host joined room: ${tokenRes.room}');
    return room;
  }

  // ── Room (Viewer / audience) ────────────────────────────────────────────────

  static Future<Room> joinAsViewer({
    required LiveKitTokenResponse tokenRes,
    void Function(RemoteParticipant, RemoteTrackPublication, Track)? onHostTrackSubscribed,
    void Function(RemoteParticipant, RemoteTrackPublication, Track)? onHostTrackUnsubscribed,
    void Function()? onTokenExpiring,
  }) async {
    final room = Room();
    final listener = room.createListener();

    listener
      ..on<TrackSubscribedEvent>((e) {
        AppLogger.logInfo(_tag, 'Track subscribed: ${e.track.kind}');
        onHostTrackSubscribed?.call(e.participant, e.publication, e.track);
      })
      ..on<TrackUnsubscribedEvent>((e) {
        AppLogger.logInfo(_tag, 'Track unsubscribed: ${e.track.kind}');
        onHostTrackUnsubscribed?.call(e.participant, e.publication, e.track);
      });

    await room.connect(
      tokenRes.wsUrl,
      tokenRes.token,
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast:       true,
      ),
    );

    AppLogger.logInfo(_tag, 'Viewer joined room: ${tokenRes.room}');
    return room;
  }

  // ── Disconnect ───────────────────────────────────────────────────────────────

  static Future<void> disconnect(Room room) async {
    await room.disconnect();
    AppLogger.logInfo(_tag, 'Disconnected from room');
  }
}
