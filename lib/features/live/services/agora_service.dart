import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:tropia/core/services/auth_service.dart';
import 'package:tropia/core/utils/logger.dart';

const _tag = 'AgoraService';

class AgoraTokenResponse {
  final String token;
  final String appId;
  final String channel;
  final int uid;
  const AgoraTokenResponse({
    required this.token,
    required this.appId,
    required this.channel,
    required this.uid,
  });
}

class AgoraService {
  AgoraService._();

  static get _dio => AuthService.instance.authorizedDio();

  // ── Token fetch ─────────────────────────────────────────────────────────────

  static Future<AgoraTokenResponse> fetchToken({
    required String channelName,
    required bool isPublisher,
    int uid = 0,
  }) async {
    final res = await _dio.post('/api/token/agora', data: {
      'channelName': channelName,
      'uid':         uid,
      'role':        isPublisher ? 'publisher' : 'subscriber',
    });
    return _parseToken(res.data as Map<String, dynamic>);
  }

  static Future<AgoraTokenResponse> fetchTokenBySession({
    required String sessionId,
    required bool isPublisher,
    int uid = 0,
  }) async {
    final res = await _dio.post('/api/token/agora', data: {
      'sessionId': sessionId,
      'uid':       uid,
      'role':      isPublisher ? 'publisher' : 'subscriber',
    });
    return _parseToken(res.data as Map<String, dynamic>);
  }

  static AgoraTokenResponse _parseToken(Map<String, dynamic> d) => AgoraTokenResponse(
    token:   d['token']   as String,
    appId:   d['appId']   as String,
    channel: d['channel'] as String,
    uid:     (d['uid'] as num).toInt(),
  );

  // ── Engine ──────────────────────────────────────────────────────────────────

  // appId luôn lấy từ server response, không hardcode trong app
  static Future<RtcEngine> createEngine(String appId) async {
    final engine = createAgoraRtcEngine();
    await engine.initialize(RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
    ));
    await engine.setAudioProfile(
      profile: AudioProfileType.audioProfileMusicHighQuality,
      scenario: AudioScenarioType.audioScenarioGameStreaming,
    );
    return engine;
  }

  // ── Host (broadcaster) ──────────────────────────────────────────────────────

  static Future<void> joinAsHost({
    required RtcEngine engine,
    required AgoraTokenResponse tokenRes,
    void Function(int uid)? onViewerJoined,
    void Function(int uid)? onViewerLeft,
    void Function()? onTokenExpiring,         // gọi khi còn ~30s
  }) async {
    await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    await engine.enableVideo();
    await engine.enableAudio();

    // Chất lượng video: 720p 15fps cho mobile livestream
    await engine.setVideoEncoderConfiguration(const VideoEncoderConfiguration(
      dimensions: VideoDimensions(width: 1280, height: 720),
      frameRate: 15,
      bitrate: 1130,
      orientationMode: OrientationMode.orientationModeAdaptive,
      degradationPreference: DegradationPreference.maintainFramerate,
    ));

    await engine.startPreview();

    engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (conn, _) =>
          AppLogger.logInfo(_tag, 'Host joined: ${conn.channelId}'),
      onUserJoined:  (_, uid, __) { onViewerJoined?.call(uid); },
      onUserOffline: (_, uid, __) { onViewerLeft?.call(uid); },
      // Token sắp hết hạn → app cần fetch token mới và renew
      onTokenPrivilegeWillExpire: (_, token) {
        AppLogger.logInfo(_tag, 'Host token expiring soon');
        onTokenExpiring?.call();
      },
      onError: (err, msg) =>
          AppLogger.logError(_tag, 'Host error $err: $msg', null, null),
    ));

    await engine.joinChannel(
      token:     tokenRes.token,
      channelId: tokenRes.channel,
      uid:       tokenRes.uid,
      options: const ChannelMediaOptions(
        clientRoleType:        ClientRoleType.clientRoleBroadcaster,
        channelProfile:        ChannelProfileType.channelProfileLiveBroadcasting,
        publishCameraTrack:    true,
        publishMicrophoneTrack: true,
        autoSubscribeAudio:    false,
        autoSubscribeVideo:    false,
      ),
    );
  }

  // ── Viewer (audience) ───────────────────────────────────────────────────────

  static Future<void> joinAsViewer({
    required RtcEngine engine,
    required AgoraTokenResponse tokenRes,
    void Function(int uid)? onHostOnline,
    void Function(int uid)? onHostOffline,
    void Function()? onTokenExpiring,
  }) async {
    // Ultra-low latency audience — không tính phút như broadcaster
    await engine.setClientRole(
      role: ClientRoleType.clientRoleAudience,
      options: const ClientRoleOptions(
        audienceLatencyLevel:
            AudienceLatencyLevelType.audienceLatencyLevelUltraLowLatency,
      ),
    );
    await engine.enableVideo();
    await engine.enableAudio();

    engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (conn, _) =>
          AppLogger.logInfo(_tag, 'Viewer joined: ${conn.channelId}'),
      // onUserJoined chỉ trigger khi host join SAU viewer
      onUserJoined:  (_, uid, __) {
        AppLogger.logInfo(_tag, 'Host online (joined): $uid');
        onHostOnline?.call(uid);
      },
      // onRemoteVideoStateChanged trigger khi host đã online từ trước
      onRemoteVideoStateChanged: (_, uid, state, reason, __) {
        AppLogger.logInfo(_tag, 'Remote video state: uid=$uid state=$state reason=$reason');
        if (state == RemoteVideoState.remoteVideoStateDecoding ||
            state == RemoteVideoState.remoteVideoStateStarting) {
          onHostOnline?.call(uid);
        } else if (state == RemoteVideoState.remoteVideoStateStopped ||
                   state == RemoteVideoState.remoteVideoStateFailed) {
          onHostOffline?.call(uid);
        }
      },
      onUserOffline: (_, uid, __) { onHostOffline?.call(uid); },
      onTokenPrivilegeWillExpire: (_, token) {
        AppLogger.logInfo(_tag, 'Viewer token expiring soon');
        onTokenExpiring?.call();
      },
      onError: (err, msg) =>
          AppLogger.logError(_tag, 'Viewer error $err: $msg', null, null),
    ));

    await engine.joinChannel(
      token:     tokenRes.token,
      channelId: tokenRes.channel,
      uid:       tokenRes.uid,
      options: const ChannelMediaOptions(
        clientRoleType:        ClientRoleType.clientRoleAudience,
        channelProfile:        ChannelProfileType.channelProfileLiveBroadcasting,
        autoSubscribeAudio:    true,
        autoSubscribeVideo:    true,
        publishCameraTrack:    false,
        publishMicrophoneTrack: false,
      ),
    );
  }

  // ── Token renewal ────────────────────────────────────────────────────────────

  /// Gọi khi nhận onTokenPrivilegeWillExpire để gia hạn token không ngắt stream.
  static Future<void> renewToken({
    required RtcEngine engine,
    required String sessionId,
    required bool isPublisher,
    required int uid,
  }) async {
    try {
      final res = await fetchTokenBySession(
        sessionId:   sessionId,
        isPublisher: isPublisher,
        uid:         uid,
      );
      await engine.renewToken(res.token);
      AppLogger.logInfo(_tag, 'Token renewed for session $sessionId');
    } catch (e) {
      AppLogger.logError(_tag, 'renewToken failed', e, null);
    }
  }
}
