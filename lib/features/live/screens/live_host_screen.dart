// =============================================================================
// live_host_screen.dart – Agora RTC broadcaster + Supabase Realtime chat
// =============================================================================

import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart' show Share;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:tropia/core/constants/app_constants.dart';
import 'package:tropia/features/live/services/agora_service.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:tropia/features/live/data/live_repository.dart';
import 'package:tropia/features/live/models/live_stream_model.dart';
import 'package:tropia/features/live/providers/live_provider.dart';
import 'package:tropia/features/live/screens/live_end_screen.dart';

const _tag = 'LiveHostScreen';

class LiveHostScreen extends StatefulWidget {
  final String title;
  final String category;
  final List<LiveProduct> products;
  final String? thumbnailUrl;
  final List<Map<String, dynamic>> coupons;

  const LiveHostScreen({
    super.key,
    required this.title,
    required this.category,
    required this.products,
    this.thumbnailUrl,
    this.coupons = const [],
  });

  @override
  State<LiveHostScreen> createState() => _LiveHostScreenState();
}

class _LiveHostScreenState extends State<LiveHostScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {

  // ─── Agora ───────────────────────────────────────────────────────────────────
  RtcEngine? _engine;
  bool _agoraReady = false;
  bool _isCameraOn = true;
  bool _isMicOn = true;
  int _localUid = 0;
  String? _startError;

  // ─── Stats from Supabase Realtime ────────────────────────────────────────────
  int _viewers    = 0;
  int _likes      = 0;
  int _cartAdds   = 0;
  int _follows    = 0;
  int _elapsedSeconds = 0;

  // ─── Chat ────────────────────────────────────────────────────────────────────
  final List<_HostChatMsg> _chatMessages = [];
  final ScrollController _chatScroll = ScrollController();
  final Set<String> _seenChatIds = {};  // tránh duplicate khi poll
  Timer? _chatPollTimer;
  Timer? _statsPollTimer;

  // ─── UI ──────────────────────────────────────────────────────────────────────
  final Set<String> _pinnedProductIds = {};
  String? _sessionId;
  bool _aiAutoReply = false;

  // ─── Timer ───────────────────────────────────────────────────────────────────
  Timer? _durationTimer;

  // ─── Animation ───────────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _setupPulse();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });

    // Agora + Supabase init after first frame (need context for provider)
    WidgetsBinding.instance.addPostFrameCallback((_) => _startLive());
  }

  // ─── Start live ───────────────────────────────────────────────────────────────

  Future<void> _startLive() async {
    // Xin quyền camera + mic trước khi init Agora
    final statuses = await [Permission.camera, Permission.microphone].request();
    if (statuses[Permission.camera] != PermissionStatus.granted ||
        statuses[Permission.microphone] != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cần cấp quyền Camera và Microphone để livestream')),
        );
        Navigator.of(context).pop();
      }
      return;
    }

    final provider = context.read<LiveProvider>();

    try {
      // 1. Publish session lên Node.js → nhận Agora channel name
      debugPrint('>>> STEP 1: publishHostStream');
      final channelName = await provider.publishHostStream(
        title:        widget.title,
        category:     widget.category,
        products:     widget.products,
        thumbnailUrl: widget.thumbnailUrl,
        coupons:      widget.coupons,
      );
      _sessionId = provider.hostSessionId;
      debugPrint('>>> STEP 1 OK: channel=$channelName');

      // 2. Lấy token từ backend (appId cũng trả về, không hardcode)
      debugPrint('>>> STEP 2: fetchToken');
      final tokenRes = await AgoraService.fetchToken(
        channelName: channelName,
        isPublisher: true,
        uid:         0,
      );
      _localUid = tokenRes.uid;
      debugPrint('>>> STEP 2 OK: appId=${tokenRes.appId} uid=${tokenRes.uid}');

      // 3. Khởi tạo engine với appId từ server
      debugPrint('>>> STEP 3: createEngine');
      _engine = await AgoraService.createEngine(tokenRes.appId);
      debugPrint('>>> STEP 3 OK');
      debugPrint('>>> STEP 4: setClientRole');
      await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      debugPrint('>>> STEP 4a: enableVideo');
      await _engine!.enableVideo();
      debugPrint('>>> STEP 4b: enableAudio');
      await _engine!.enableAudio();
      debugPrint('>>> STEP 4c: setVideoEncoderConfiguration');
      await _engine!.setVideoEncoderConfiguration(const VideoEncoderConfiguration(
        dimensions: VideoDimensions(width: 640, height: 480),
        frameRate: 15,
        bitrate: 500,
        orientationMode: OrientationMode.orientationModeAdaptive,
        degradationPreference: DegradationPreference.maintainFramerate,
      ));

      // Đăng ký event handler TRƯỚC khi startPreview/joinChannel
      _engine!.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (conn, _) =>
            AppLogger.logInfo(_tag, 'Host joined: ${conn.channelId}'),
        onLocalVideoStateChanged: (VideoSourceType source, LocalVideoStreamState state, LocalVideoStreamReason reason) {
          AppLogger.logInfo(_tag, 'LocalVideo state=$state reason=$reason');
          if (state == LocalVideoStreamState.localVideoStreamStateCapturing ||
              state == LocalVideoStreamState.localVideoStreamStateEncoding) {
            if (mounted && !_agoraReady) setState(() => _agoraReady = true);
          }
        },
        onUserJoined:  (_, uid, __) { if (mounted) setState(() => _viewers++); },
        onUserOffline: (_, uid, __) { if (mounted) setState(() => _viewers = (_viewers - 1).clamp(0, 999999)); },
        onTokenPrivilegeWillExpire: (_, token) => _renewHostToken(channelName),
        onError: (err, msg) => AppLogger.logError(_tag, 'Agora error $err: $msg', null, null),
      ));

      debugPrint('>>> STEP 4d: startPreview');
      await _engine!.startPreview();
      debugPrint('>>> STEP 4d OK: startPreview called');

      // Fallback: nếu sau 3 giây camera chưa trigger event, vẫn hiển thị preview
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && !_agoraReady) setState(() => _agoraReady = true);
      });

      _engine!.joinChannel(
        token:     tokenRes.token,
        channelId: tokenRes.channel,
        uid:       tokenRes.uid,
        options: const ChannelMediaOptions(
          clientRoleType:         ClientRoleType.clientRoleBroadcaster,
          channelProfile:         ChannelProfileType.channelProfileLiveBroadcasting,
          publishCameraTrack:     true,
          publishMicrophoneTrack: true,
          autoSubscribeAudio:     false,
          autoSubscribeVideo:     false,
        ),
      );

      // 4. Start polling chat + stats — dùng _sessionId đã gán ở trên
      _startPolling();

      AppLogger.logUserEvent(action: 'host_live_started', context: _tag,
          metadata: {'title': widget.title, 'channel': channelName});
    } catch (e, st) {
      AppLogger.logError(_tag, 'startLive failed', e, st);
      if (mounted) setState(() => _startError = e.toString());
    }
  }

  Future<void> _renewHostToken(String channelName) async {
    if (_engine == null) return;
    await AgoraService.renewToken(
      engine:      _engine!,
      sessionId:   _sessionId ?? channelName,
      isPublisher: true,
      uid:         _localUid,
    );
  }

  // ─── Polling ──────────────────────────────────────────────────────────────────

  void _startPolling() {
    if (_sessionId == null) return;

    // Poll chat mỗi 3 giây
    _chatPollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || _sessionId == null) return;
      try {
        final rows = await LiveRepository.instance.fetchRecentChats(_sessionId!);
        for (final row in rows) {
          final id = row['id']?.toString() ?? '';
          if (id.isEmpty || _seenChatIds.contains(id)) continue;
          _seenChatIds.add(id);
          final message  = row['message']?.toString() ?? '';
          final username = (row['username'] ?? row['user_name'])?.toString() ?? 'Khách';
          // is_host từ DB, hoặc fallback: message bot bắt đầu bằng 🤖, hoặc username là bot/host
          final isHostMsg = (row['is_host'] as bool?) == true
              || message.startsWith('🤖')
              || message.startsWith('🎫 Coupon:')
              || username.contains('Trợ lý');
          if (message.isNotEmpty) {
            // Bỏ qua bot/host reply — chỉ xử lý tin viewer thực
            if (!isHostMsg) {
              _addChat(username: username, message: message);
              _maybeAiReply(message);
            }
          }
        }
      } catch (e) {
        AppLogger.logError(_tag, 'chat poll error', e, null);
      }
    });

    // Poll stats mỗi 5 giây
    _statsPollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || _sessionId == null) return;
      try {
        final stats = await LiveRepository.instance.fetchSessionStats(_sessionId!);
        if (mounted) {
          setState(() {
            _viewers  = (stats['viewer_count']   as num?)?.toInt() ?? _viewers;
            _likes    = (stats['like_count']      as num?)?.toInt() ?? _likes;
            _cartAdds = (stats['cart_add_count']  as num?)?.toInt() ?? _cartAdds;
            _follows  = (stats['follow_count']    as num?)?.toInt() ?? _follows;
          });
        }
      } catch (e) {
        AppLogger.logError(_tag, 'stats poll error', e, null);
      }
    });
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _engine?.muteLocalVideoStream(true);
    } else if (state == AppLifecycleState.resumed) {
      if (_isCameraOn) _engine?.muteLocalVideoStream(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _durationTimer?.cancel();
    _chatPollTimer?.cancel();
    _statsPollTimer?.cancel();
    _pulseCtrl.dispose();
    _chatScroll.dispose();
    _engine?.leaveChannel();
    _engine?.release();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ─── Camera / mic controls ────────────────────────────────────────────────────

  void _toggleCamera() {
    setState(() => _isCameraOn = !_isCameraOn);
    _engine?.muteLocalVideoStream(!_isCameraOn);
  }

  void _toggleMic() {
    setState(() => _isMicOn = !_isMicOn);
    _engine?.muteLocalAudioStream(!_isMicOn);
  }

  Future<void> _flipCamera() async {
    await _engine?.switchCamera();
  }

  // ─── Chat ─────────────────────────────────────────────────────────────────────

  void _addChat({required String username, required String message, bool isHost = false}) {
    if (!mounted) return;
    setState(() {
      _chatMessages.add(_HostChatMsg(username: username, message: message, isHost: isHost));
      if (_chatMessages.length > 50) _chatMessages.removeAt(0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(_chatScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _toggleAiAutoReply() {
    setState(() => _aiAutoReply = !_aiAutoReply);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_aiAutoReply ? '🤖 Bot AI đã bật – tự động trả lời câu hỏi của người xem' : 'Bot AI đã tắt'),
        duration: const Duration(seconds: 2),
        backgroundColor: _aiAutoReply ? AppColors.primary : Colors.grey[700],
      ),
    );
    AppLogger.logUserEvent(
      action: _aiAutoReply ? 'ai_bot_enabled' : 'ai_bot_disabled',
      context: _tag,
      metadata: {'sessionId': _sessionId},
    );
  }

  Future<void> _maybeAiReply(String question) async {
    if (!_aiAutoReply || _sessionId == null || !mounted) return;
    try {
      final relevantProducts = _pinnedProductIds.isNotEmpty
          ? widget.products.where((p) => _pinnedProductIds.contains(p.id)).toList()
          : widget.products;
      final allNames = relevantProducts.isNotEmpty
          ? relevantProducts.map((p) => p.name).join(', ')
          : widget.title;
      final category = relevantProducts.isNotEmpty
          ? relevantProducts.first.category
          : widget.category;
      final reply = await LiveRepository.instance.fetchAiReply(
        sessionId:   _sessionId!,
        question:    question,
        productName: allNames,
        category:    category,
      );
      if (reply != null && reply.isNotEmpty && mounted) {
        await LiveRepository.instance.sendChat(
          sessionId: _sessionId!,
          message:   '🤖 $reply',
          isHost:    true,
        );
        _addChat(username: 'Trợ lý AI', message: '🤖 $reply', isHost: true);
      }
    } catch (e) {
      AppLogger.logError(_tag, 'ai auto-reply failed', e, null);
    }
  }

  // ─── End live ─────────────────────────────────────────────────────────────────

  Future<void> _confirmEnd() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.hostLiveEnd),
        content: const Text(AppStrings.hostLiveEndConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(AppStrings.actionCancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(AppStrings.hostLiveEnd),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final provider = context.read<LiveProvider>();
      final nav      = Navigator.of(context);

      // Kết thúc session trước để DB flush hết pending increments (follow/cart)
      await provider.unpublishHostStream();

      // Lấy stats sau khi session đã ended — follow_count, cart_add_count đã ghi đủ
      int finalViewers  = _viewers;
      int finalLikes    = _likes;
      int finalCartAdds = _cartAdds;
      int finalFollows  = _follows;
      if (_sessionId != null) {
        try {
          final stats = await LiveRepository.instance.fetchSessionStats(_sessionId!);
          finalViewers  = (stats['viewer_count']  as num?)?.toInt() ?? finalViewers;
          finalLikes    = (stats['like_count']     as num?)?.toInt() ?? finalLikes;
          finalCartAdds = (stats['cart_add_count'] as num?)?.toInt() ?? finalCartAdds;
          finalFollows  = (stats['follow_count']   as num?)?.toInt() ?? finalFollows;
        } catch (_) {}
      }
      await _engine?.leaveChannel();
      if (!mounted) return;
      nav.pushReplacement(MaterialPageRoute(
        builder: (_) => LiveEndScreen(
          title:        widget.title,
          sessionId:    _sessionId ?? '',
          peakViewers:  finalViewers,
          totalLikes:   finalLikes,
          cartAddCount: finalCartAdds,
          followCount:  finalFollows,
        ),
      ));
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────────

  void _setupPulse() {
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  String get _durationText {
    final h = _elapsedSeconds ~/ 3600;
    final m = (_elapsedSeconds % 3600) ~/ 60;
    final s = _elapsedSeconds % 60;
    return h > 0 ? '${_p(h)}:${_p(m)}:${_p(s)}' : '${_p(m)}:${_p(s)}';
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  String _fmt(double price) {
    if (price >= 1000000) return '${(price / 1000000).toStringAsFixed(1)}tr';
    if (price >= 1000) return '${(price / 1000).toStringAsFixed(0)}K';
    return price.toStringAsFixed(0);
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(fit: StackFit.expand, children: [
        _buildVideoLayer(),
        Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),
        Positioned(left: 0, right: 110, bottom: 170, top: 100, child: _buildChat()),
        if (_pinnedProductIds.isNotEmpty)
          Positioned(left: AppSizes.sm, bottom: 170, child: _buildPinnedProducts()),
        Positioned(right: AppSizes.sm, bottom: 170, child: _buildSideControls()),
        Positioned(left: 0, right: 0, bottom: 0, child: _buildBottomBar()),
      ]),
    );
  }

  // ─── Video layer ──────────────────────────────────────────────────────────────

  Widget _buildVideoLayer() {
    if (!_agoraReady || !_isCameraOn) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF1B2838), Color(0xFF0D1117), Color(0xFF1A1F2E)],
          ),
        ),
        child: Center(child: _startError != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                  const SizedBox(height: 12),
                  const Text('Không thể bắt đầu live', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(_startError!, style: const TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () { setState(() => _startError = null); _startLive(); },
                    child: const Text('Thử lại', style: TextStyle(color: Colors.white70)),
                  ),
                ]),
              )
            : !_agoraReady
                ? const CircularProgressIndicator(color: Colors.white38)
                : const Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.videocam_off, color: Colors.white24, size: 56),
                    SizedBox(height: AppSizes.sm),
                    Text('Camera đang tắt', style: TextStyle(color: Colors.white30, fontSize: AppSizes.fontMd)),
                  ]),
        ),
      );
    }

    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: _engine!,
        canvas: const VideoCanvas(uid: 0), // 0 = local
      ),
    );
  }

  // ─── Top bar ──────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + AppSizes.xs,
        left: AppSizes.sm, right: AppSizes.sm, bottom: AppSizes.xs,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: _confirmEnd,
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: Colors.black45,
                borderRadius: BorderRadius.circular(AppSizes.radiusFull)),
            child: const Icon(Icons.close, color: Colors.white, size: 20),
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        _buildLiveBadge(),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: Text(widget.title,
            style: const TextStyle(color: Colors.white, fontSize: AppSizes.fontSm, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis),
        ),
        _buildChip(icon: Icons.timer_outlined, label: _durationText),
        const SizedBox(width: AppSizes.xs),
        _buildChip(
          icon: Icons.visibility_outlined,
          label: _viewers >= 1000 ? '${(_viewers / 1000).toStringAsFixed(1)}K' : '$_viewers',
        ),
      ]),
    );
  }

  Widget _buildLiveBadge() {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Opacity(
        opacity: _pulse.value,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.liveRed,
            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, color: Colors.white, size: 6),
            SizedBox(width: 3),
            Text('LIVE', style: TextStyle(color: Colors.white, fontSize: AppSizes.fontXs, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }

  Widget _buildChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 4),
      decoration: BoxDecoration(color: Colors.black54,
          borderRadius: BorderRadius.circular(AppSizes.radiusFull)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white70, size: 12),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: AppSizes.fontXs, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ─── Chat overlay ─────────────────────────────────────────────────────────────

  Widget _buildChat() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header label
        Padding(
          padding: const EdgeInsets.only(left: AppSizes.sm, bottom: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            ),
            child: const Text(
              'Chat người mua',
              style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        Expanded(
          child: _chatMessages.isEmpty
              ? const Center(
                  child: Text(
                    'Chưa có tin nhắn nào',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  controller: _chatScroll,
                  padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.xs),
                  itemCount: _chatMessages.length,
                  itemBuilder: (_, i) {
          final m = _chatMessages[i];
          final isBot = m.username.startsWith('Trợ lý');
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: isBot
                    ? Colors.blue.withValues(alpha: 0.5)
                    : m.isHost
                        ? AppColors.gold.withValues(alpha: 0.5)
                        : Colors.white24,
                child: Text(
                  isBot ? '🤖' : m.username[0].toUpperCase(),
                  style: TextStyle(
                    fontSize: isBot ? 8 : 9,
                    color: isBot ? Colors.blue[200] : m.isHost ? AppColors.gold : Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isBot
                        ? const Color(0xFF1A237E).withValues(alpha: 0.82)
                        : m.isHost
                            ? const Color(0xFFB8860B).withValues(alpha: 0.75)
                            : Colors.black.withValues(alpha: 0.65),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(2), topRight: Radius.circular(12),
                      bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: RichText(
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    text: TextSpan(children: [
                      TextSpan(
                        text: m.username,
                        style: TextStyle(
                          color: isBot ? const Color(0xFF90CAF9) : m.isHost ? AppColors.gold : const Color(0xFFE0E0E0),
                          fontSize: 12, fontWeight: FontWeight.w700, height: 1.4,
                          shadows: const [Shadow(color: Colors.black87, blurRadius: 4)],
                        ),
                      ),
                      const TextSpan(text: '  '),
                      TextSpan(
                        text: m.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12, height: 1.4,
                          shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ]),
          );
                },
              ),
        ),
      ],
    );
  }

  // ─── Pinned products ──────────────────────────────────────────────────────────

  Widget _buildPinnedProducts() {
    final pinned = widget.products.where((p) => _pinnedProductIds.contains(p.id)).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: pinned.map((product) => Container(
        width: 130,
        margin: const EdgeInsets.only(bottom: AppSizes.xs),
        padding: const EdgeInsets.all(AppSizes.xs),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.6)),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            child: Image.network(product.imageUrl, width: 40, height: 40, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(width: 40, height: 40, color: AppColors.surfaceVariant)),
          ),
          const SizedBox(width: AppSizes.xs),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(product.name, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${_fmt(product.salePrice)}đ',
              style: const TextStyle(color: AppColors.secondary, fontSize: 10, fontWeight: FontWeight.w700)),
          ])),
          GestureDetector(
            onTap: () {
              setState(() => _pinnedProductIds.remove(product.id));
              _syncPinnedToProvider();
            },
            child: const Icon(Icons.close, color: Colors.white54, size: 14),
          ),
        ]),
      )).toList(),
    );
  }

  // ─── Side controls ────────────────────────────────────────────────────────────

  Widget _buildSideControls() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _SideBtn(icon: _isMicOn ? Icons.mic : Icons.mic_off,
        label: _isMicOn ? 'Mic' : 'Tắt', color: _isMicOn ? Colors.white : AppColors.error,
        onTap: _toggleMic),
      const SizedBox(height: AppSizes.sm),
      _SideBtn(icon: _isCameraOn ? Icons.videocam : Icons.videocam_off,
        label: _isCameraOn ? 'Cam' : 'Tắt', color: _isCameraOn ? Colors.white : AppColors.error,
        onTap: _toggleCamera),
      const SizedBox(height: AppSizes.sm),
      _SideBtn(icon: Icons.flip_camera_android, label: 'Xoay', color: Colors.white, onTap: _flipCamera),
      const SizedBox(height: AppSizes.sm),
      _SideBtn(icon: Icons.share_outlined, label: 'Chia sẻ', color: Colors.white,
        onTap: () => _shareHostLive()),
      if (widget.products.isNotEmpty) ...[
        const SizedBox(height: AppSizes.sm),
        _SideBtn(icon: Icons.push_pin_outlined, label: 'Ghim SP', color: Colors.white,
          onTap: _showPinSheet),
      ],
      const SizedBox(height: AppSizes.sm),
      _SideBtn(icon: Icons.local_offer_outlined, label: 'Coupon', color: Colors.white,
        onTap: _showCouponSheet),
      const SizedBox(height: AppSizes.sm),
      _SideBtn(
        icon: Icons.smart_toy_outlined,
        label: 'Bot AI',
        color: _aiAutoReply ? AppColors.primary : Colors.white,
        onTap: _toggleAiAutoReply,
        active: _aiAutoReply,
      ),
    ]);
  }

  void _showCouponSheet() {
    if (_sessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Buổi live chưa sẵn sàng')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CouponBroadcastSheet(
        sessionId: _sessionId!,
        onBroadcast: (code) {
          _addChat(username: 'Trợ lý Live', message: '🎫 Coupon: $code – Áp dụng khi đặt hàng!');
          AppLogger.logUserEvent(
            action: 'host_coupon_sent',
            context: _tag,
            metadata: {'code': code},
          );
        },
      ),
    );
  }

  Future<void> _shareHostLive() async {
    if (_sessionId == null) return;
    final link = 'https://tropia.app/live/$_sessionId';
    final text = '🔴 ${widget.title} – Xem live ngay!\n$link';
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã copy link live vào clipboard!')),
        );
      }
    } else {
      await Share.share(text);
    }
  }

  void _syncPinnedToProvider() {
    if (_sessionId == null) return;
    context.read<LiveProvider>().updatePinnedProducts(_sessionId!, Set.of(_pinnedProductIds));
  }

  void _showPinSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSizes.md, AppSizes.md, AppSizes.md, AppSizes.xs),
            child: Row(children: [
              const Expanded(
                child: Text(AppStrings.hostLivePinProduct,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: AppSizes.fontLg)),
              ),
              if (_pinnedProductIds.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() => _pinnedProductIds.clear());
                    setSheetState(() {});
                    _syncPinnedToProvider();
                  },
                  child: const Text('Bỏ tất cả', style: TextStyle(color: AppColors.error)),
                ),
            ]),
          ),
          ...widget.products.map((p) {
            final isPinned = _pinnedProductIds.contains(p.id);
            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                child: Image.network(p.imageUrl, width: 40, height: 40, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(width: 40, height: 40, color: AppColors.surfaceVariant)),
              ),
              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${_fmt(p.salePrice)}đ',
                style: const TextStyle(color: AppColors.secondary, fontWeight: FontWeight.w600)),
              trailing: isPinned
                  ? const Icon(Icons.check_circle, color: AppColors.primary)
                  : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
              onTap: () {
                setState(() {
                  if (isPinned) {
                    _pinnedProductIds.remove(p.id);
                  } else {
                    _pinnedProductIds.add(p.id);
                  }
                });
                setSheetState(() {});
                _syncPinnedToProvider();
              },
            );
          }),
          const SizedBox(height: AppSizes.lg),
        ]),
      ),
    );
  }

  // ─── Bottom bar ───────────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.only(
        left: AppSizes.md, right: AppSizes.md,
        top: AppSizes.sm,
        bottom: MediaQuery.of(context).padding.bottom + AppSizes.sm,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter, end: Alignment.topCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _StatBox(icon: Icons.visibility_outlined,    value: '$_viewers',  label: 'Người xem'),
          _StatBox(icon: Icons.shopping_cart_outlined,  value: '$_cartAdds', label: 'Giỏ hàng'),
          _StatBox(icon: Icons.person_add_outlined,     value: '$_follows',  label: 'Theo dõi'),
          _StatBox(icon: Icons.favorite_outline,        value: '$_likes',    label: 'Thích'),
        ]),
        const SizedBox(height: AppSizes.sm),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _confirmEnd,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusMd)),
            ),
            icon: const Icon(Icons.stop_circle_outlined, size: 20),
            label: const Text(AppStrings.hostLiveEnd,
              style: TextStyle(fontSize: AppSizes.fontMd, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}

// ─── Helper widgets ───────────────────────────────────────────────────────────

class _HostChatMsg {
  final String username;
  final String message;
  final bool isHost;
  const _HostChatMsg({required this.username, required this.message, this.isHost = false});
}

class _SideBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool active;
  const _SideBtn({required this.icon, required this.label, required this.color, this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: active ? AppColors.primary.withValues(alpha: 0.25) : Colors.black54,
            shape: BoxShape.circle,
            border: Border.all(color: active ? AppColors.primary : Colors.white24, width: active ? 1.5 : 0.5),
          ),
          child: Icon(icon, color: onTap != null ? color : Colors.white24, size: AppSizes.iconMd),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: active ? AppColors.primary : Colors.white70, fontSize: 10)),
      ]),
    );
  }
}

class _StatBox extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _StatBox({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: Colors.white70, size: 16),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: AppSizes.fontSm, fontWeight: FontWeight.w700)),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
    ]);
  }
}

// ─── Bottom sheet: load + broadcast coupons từ Supabase ──────────────────────

class _CouponBroadcastSheet extends StatefulWidget {
  final String sessionId;
  final void Function(String code) onBroadcast;

  const _CouponBroadcastSheet({
    required this.sessionId,
    required this.onBroadcast,
  });

  @override
  State<_CouponBroadcastSheet> createState() => _CouponBroadcastSheetState();
}

class _CouponBroadcastSheetState extends State<_CouponBroadcastSheet> {
  List<Map<String, dynamic>> _coupons = [];
  bool _loading = true;
  final Set<String> _broadcasting = {};

  @override
  void initState() {
    super.initState();
    _loadCoupons();
  }

  Future<void> _loadCoupons() async {
    final data = await LiveRepository.instance.fetchLiveCoupons(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _coupons = data;
      _loading = false;
    });
  }

  Future<void> _broadcast(Map<String, dynamic> coupon) async {
    final code = coupon['code'] as String;
    if (_broadcasting.contains(code)) return;
    setState(() => _broadcasting.add(code));
    try {
      await LiveRepository.instance.broadcastCoupon(
        sessionId: widget.sessionId,
        couponCode: code,
      );
      widget.onBroadcast(code);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi phát coupon: $e')),
        );
        setState(() => _broadcasting.remove(code));
      }
    }
  }

  String _discountLabel(Map<String, dynamic> c) {
    final type  = c['discount_type'] as String? ?? 'fixed';
    final value = (c['discount_value'] as num?)?.toDouble() ?? 0;
    if (value == 0) return c['code'] as String;
    if (type == 'percent') return 'Giảm ${value.toInt()}%';
    if (value >= 1000) return 'Giảm ${(value / 1000).toInt()}Kđ';
    return 'Giảm ${value.toInt()}đ';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Container(width: 36, height: 4,
          decoration: BoxDecoration(color: AppColors.divider,
            borderRadius: BorderRadius.circular(2))),
        const Padding(
          padding: EdgeInsets.all(AppSizes.md),
          child: Text('Coupon buổi live',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: AppSizes.fontLg)),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(AppSizes.lg),
            child: CircularProgressIndicator(),
          )
        else if (_coupons.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSizes.lg),
            child: Text('Chưa có coupon nào. Tạo coupon trong trang quản lý shop.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary)),
          )
        else
          ..._coupons.map((c) {
            final code = c['code'] as String;
            final isBusy = _broadcasting.contains(code);
            return ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.primaryContainer, shape: BoxShape.circle),
                child: const Icon(Icons.local_offer, color: AppColors.primary, size: 20),
              ),
              title: Text(code,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: AppSizes.fontMd)),
              subtitle: Text(_discountLabel(c),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: AppSizes.fontXs)),
              trailing: ElevatedButton(
                onPressed: isBusy ? null : () => _broadcast(c),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
                  minimumSize: const Size(60, 32),
                  textStyle: const TextStyle(fontSize: AppSizes.fontXs, fontWeight: FontWeight.w700),
                ),
                child: isBusy
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Phát'),
              ),
            );
          }),
        SizedBox(height: AppSizes.lg + MediaQuery.of(context).padding.bottom),
      ],
    );
  }
}
