// =============================================================================
// live_setup_screen.dart – Shopee-style 2-step live setup
// =============================================================================
// Step 1: Camera preview + title + category + products → "TIẾP THEO"
// Step 2: Review panel with toolbar grid → "Bắt đầu Livestream"
// =============================================================================

import 'dart:async';
import 'dart:io';

import 'package:apivideo_live_stream/apivideo_live_stream.dart' as alive;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:tropia/core/constants/app_constants.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:tropia/features/live/data/live_repository.dart';
import 'package:tropia/features/live/data/live_socket.dart';
import 'package:tropia/features/live/models/live_stream_model.dart';
import 'package:tropia/features/live/providers/live_provider.dart';
import 'package:tropia/features/live/screens/live_end_screen.dart';
import 'package:tropia/features/live/screens/seller_product_picker_screen.dart';
import 'package:tropia/features/live/widgets/face_sticker_overlay.dart';
import 'package:tropia/features/live/services/live_foreground_service.dart';
import 'package:tropia/features/live/widgets/live_chat_widget.dart';

const _tag = 'LiveSetupScreen';

class LiveSetupScreen extends StatefulWidget {
  const LiveSetupScreen({super.key});

  @override
  State<LiveSetupScreen> createState() => _LiveSetupScreenState();
}

class _LiveSetupScreenState extends State<LiveSetupScreen>
    with WidgetsBindingObserver {
  final _titleController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _scrollCtrl = ScrollController();

  String _selectedCategory = 'Thực phẩm';
  final List<LiveProduct> _selectedProducts = [];
  final List<_LiveCoupon> _coupons = [];
  int _step = 1; // 1 = setup form, 2 = confirm/start

  // ─── Camera (preview, package:camera) ────────────────────────────────────────
  List<CameraDescription> _cameras = [];
  CameraController? _cameraController;
  int _cameraIndex = 0;
  bool _isCameraOn = true;
  bool _isMicOn = true;
  // AR face sticker overlay choice (tai thỏ / tai mèo). Host-only preview;
  // never pushed to the RTMP encoder. See FaceStickerOverlay docs.
  FaceStickerKind _faceSticker = FaceStickerKind.none;
  bool _cameraReady = false;
  String? _cameraError;

  // ─── RTMP publisher (apivideo_live_stream) ───────────────────────────────────
  // package:camera owns the device while previewing; once the user taps
  // "Bắt đầu Livestream" we dispose the CameraController and hand the
  // camera over to ApiVideoLiveStreamController which pushes RTMP to SRS.
  alive.ApiVideoLiveStreamController? _aliveController;
  alive.CameraPosition _alivePosition = alive.CameraPosition.front;
  bool _isLive = false;
  bool _isStarting = false;
  String? _sessionId;
  // live_session_products.id currently highlighted ("đang giới thiệu").
  // Null = no pin. Synced from server in stats events so a host on two
  // devices stays consistent.
  String? _pinnedProductId;
  bool _pinBusy = false;
  // Disables the "Phát coupon" buttons while a re-announce POST is in
  // flight, so a quick double-tap doesn't fire two announces.
  bool _couponBusy = false;
  DateTime? _liveStartedAt;
  Timer? _liveTicker;
  Duration _liveElapsed = Duration.zero;
  // Cached publish credentials so we can re-attach RTMP after the user
  // backgrounds the app (Android pauses the activity → camera + RTMP
  // socket are torn down by the system; on resume we re-init the
  // ApiVideoLiveStreamController and re-call startStreaming with the
  // same key).
  String? _rtmpServer;
  String? _rtmpStreamKey;
  bool _isReattaching = false;

  // Realtime stats polled every 5s from /api/live/streams/:id/stats. We keep
  // local copies (not just LiveProvider.currentStream) so the host overlay
  // also tracks cart/follow counters which aren't on the stream model.
  int _statViewers = 0;
  int _statLikes = 0;
  int _statCartAdds = 0;
  int _statFollows = 0;
  // Host overlay used to poll /stats every 5s. Now subscribes to the
  // same per-session WebSocket viewers use — counters update in <100ms
  // on join/leave/like/cart-add/follow instead of waiting for the next
  // tick.
  LiveSocket? _statsSocket;
  bool _botEnabled = false;
  bool _botBusy = false;

  static const _categories = [
    'Thực phẩm', 'Mẹ & Bé', 'Thời trang', 'Giày dép',
    'Mỹ phẩm', 'Đồ uống', 'Hạt khô', 'Rau củ quả',
  ];

  // Toolbar items for step 2
  static const _toolbarItems = [
    (Icons.shopping_bag_outlined, 'Giỏ hàng'),
    (Icons.card_giftcard_outlined, 'Thưởng Xu'),
    (Icons.campaign_outlined, 'Quảng cáo'),
    (Icons.camera_alt_outlined, 'Camera'),
    (Icons.blur_on_outlined, 'Phòng xanh'),
    (Icons.face_retouching_natural, 'Làm đẹp'),
    (Icons.auto_awesome_outlined, 'Hiệu ứng'),
    (Icons.visibility_outlined, 'Xem thẫm'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isLive) {
      // Android pauses the activity when the user switches apps, which
      // releases the camera and tears down the RTMP socket — apivideo
      // doesn't auto-reconnect. We dispose the controller on pause (so
      // the camera can be re-acquired cleanly) and rebuild + restart
      // streaming on resume using the cached server/streamKey.
      if (state == AppLifecycleState.paused) {
        final ctrl = _aliveController;
        _aliveController = null;
        if (mounted) setState(() {}); // swap preview off
        ctrl?.stopStreaming().catchError((_) {});
        ctrl?.dispose();
      } else if (state == AppLifecycleState.resumed) {
        if (_aliveController == null) _reattachRtmp();
      }
      return;
    }

    if (state == AppLifecycleState.paused) {
      _cameraController?.dispose();
      _cameraController = null;
      if (mounted) setState(() => _cameraReady = false);
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraController == null) _initCamera();
    }
  }

  Future<void> _reattachRtmp() async {
    if (_isReattaching) return;
    final server = _rtmpServer;
    final key = _rtmpStreamKey;
    if (server == null || key == null) return;
    _isReattaching = true;
    try {
      final ctrl = alive.ApiVideoLiveStreamController(
        initialAudioConfig: alive.AudioConfig(),
        // 720p @ 1.5 Mbps — cap bitrate well below the package default
        // (2 Mbps) so buyers on 3G / weak 4G can keep up. Above ~1.8 Mbps
        // mobile viewers stall every few seconds; below ~1 Mbps the
        // video looks blocky on a phone screen. 1.5 Mbps is the Shopee/
        // TikTok Live sweet spot for 720x1280 portrait at 30fps.
        initialVideoConfig: alive.VideoConfig(
          bitrate: 1500000,
          resolution: alive.Resolution.RESOLUTION_720,
          fps: 30,
        ),
        initialCameraPosition: _alivePosition,
        onError: (e) {
          AppLogger.logError(_tag, 'apivideo reattach error', e, null);
        },
      );
      await ctrl.initialize();
      // The foreground service may have been stopped by the OS too
      // (rare but possible if device was deep-sleeping). Re-start it
      // before kicking RTMP back up so we're priority-anchored again.
      await LiveForegroundService.start(
        title: _titleController.text.trim().isEmpty
            ? 'Đang livestream'
            : _titleController.text.trim(),
      );
      await ctrl.startStreaming(streamKey: key, url: server);
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() => _aliveController = ctrl);
    } catch (e) {
      AppLogger.logError(_tag, 'reattach failed', e, null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không kết nối lại được: $e')),
        );
      }
    } finally {
      _isReattaching = false;
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _cameraError = 'Không tìm thấy camera');
        return;
      }
      _cameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      if (_cameraIndex < 0) _cameraIndex = 0;
      await _startCamera(_cameraIndex);
    } catch (e) {
      AppLogger.logError(_tag, 'Camera init failed', e, null);
      setState(() => _cameraError = 'Không thể khởi động camera: $e');
    }
  }

  Future<void> _startCamera(int index) async {
    final old = _cameraController;
    if (old != null) {
      await old.dispose();
      _cameraController = null;
    }
    final ctrl = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: _isMicOn,
      // nv21 (Android) / bgra8888 (iOS) so the same controller can both
      // render the preview AND feed ML Kit Face Detection for the AR
      // sticker overlay. JPEG (the previous setting) is opaque to ML Kit
      // — it'd just drop every frame, which is why "Tai thỏ" looked
      // active in the toolbar but no emoji ever appeared on the face.
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    _cameraController = ctrl;
    try {
      await ctrl.initialize();
      if (mounted) setState(() { _cameraReady = true; _cameraError = null; });
    } on CameraException catch (e) {
      AppLogger.logError(_tag, 'Camera start failed', e, null);
      setState(() {
        _cameraReady = false;
        _cameraError = e.description ?? 'Lỗi camera';
      });
    }
  }

  Future<void> _flipCamera() async {
    if (_aliveController != null) {
      final next = _alivePosition == alive.CameraPosition.back
          ? alive.CameraPosition.front
          : alive.CameraPosition.back;
      try {
        await _aliveController!.setCameraPosition(next);
        if (mounted) setState(() => _alivePosition = next);
      } catch (e) {
        AppLogger.logError(_tag, 'flip alive camera failed', e, null);
      }
      return;
    }
    if (_cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    setState(() => _cameraReady = false);
    await _startCamera(_cameraIndex);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveTicker?.cancel();
    _statsSocket?.close();
    _statsSocket = null;
    _titleController.dispose();
    _scrollCtrl.dispose();
    final ctrl = _cameraController;
    _cameraController = null;
    ctrl?.dispose();
    final live = _aliveController;
    _aliveController = null;
    live?.dispose();
    // Defensive: if the user navigated out of the screen via system
    // back without tapping "Kết thúc Live", make sure the foreground
    // service notification doesn't linger. Safe to call when no
    // service is running — the Service handles ACTION_STOP by no-op'ing.
    if (_isLive) {
      LiveForegroundService.stop();
    }
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        // Block system back while live — user must tap "Dừng phát" so the
        // backend session is properly closed.
        canPop: !_isLive,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _isLive && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đang livestream — hãy bấm "Dừng phát" trước')),
            );
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              // Full-screen camera preview as background
              Positioned.fill(child: _buildCameraBackground()),
              // Step overlay
              _step == 1 ? _buildStep1Overlay() : _buildStep2Overlay(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Camera background ────────────────────────────────────────────────────────

  Widget _buildCameraBackground() {
    // When streaming, swap to the apivideo preview (it owns the camera now).
    if (_aliveController != null) {
      return alive.ApiVideoCameraPreview(controller: _aliveController!);
    }
    if (_cameraError != null) return _buildCameraErrorBg();
    if (!_cameraReady) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white38)),
      );
    }
    if (!_isCameraOn) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: Icon(Icons.videocam_off, color: Colors.white24, size: 56)),
      );
    }
    // Fill the host's screen with the camera preview the same way Shopee
    // Live and ApiVideoCameraPreview do: scale the sensor frame so that its
    // shorter side covers the parent. `package:camera` reports the sensor
    // aspect ratio as landscape (16:9 ≈ 1.78) even on portrait phones, so
    // the default behaviour leaves either huge black bars (strict
    // AspectRatio) or a stretched preview (raw widget). Transform.scale
    // with 1/(sensorAr * screenAr) gives the cover-fit fill the host
    // expects, with a small symmetric crop on the long axis.
    final ctrl = _cameraController!;
    final sensorAr = ctrl.value.isInitialized && ctrl.value.aspectRatio > 0
        ? ctrl.value.aspectRatio
        : 16 / 9;
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final screenAr = constraints.maxWidth / constraints.maxHeight;
          var scale = sensorAr * screenAr;
          if (scale < 1) scale = 1 / scale;
          return ClipRect(
            child: Center(
              child: Transform.scale(
                scale: scale,
                child: AspectRatio(
                  aspectRatio: 1 / sensorAr,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(ctrl),
                      // AR sticker is purely host-side preview; the RTMP
                      // push still encodes the raw camera frame, so
                      // buyers see the unfiltered face. Documented in
                      // face_sticker_overlay.dart.
                      FaceStickerOverlay(
                        cameraController: ctrl,
                        sticker: _faceSticker,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCameraErrorBg() {
    return Container(
      color: const Color(0xFF111111),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, color: Colors.white38, size: 48),
            const SizedBox(height: AppSizes.sm),
            Text(
              _cameraError ?? 'Lỗi camera',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: AppSizes.fontSm),
            ),
            const SizedBox(height: AppSizes.md),
            TextButton(
              onPressed: _initCamera,
              child: const Text('Thử lại', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Step 1: Form overlay ─────────────────────────────────────────────────────

  Widget _buildStep1Overlay() {
    return Column(
      children: [
        // Top bar
        _buildTopBar(),

        // Middle: preview badge + "Bạn" label float freely
        Expanded(
          child: Stack(
            children: [
              // PREVIEW badge top-left
              Positioned(
                top: AppSizes.md,
                left: AppSizes.md,
                child: _buildPreviewBadge(),
              ),
              // "Bạn" label bottom-left
              Positioned(
                bottom: AppSizes.md,
                left: AppSizes.md,
                child: _buildUserLabel(),
              ),
              // Camera controls bottom-right
              Positioned(
                bottom: AppSizes.md,
                right: AppSizes.md,
                child: _buildCameraControlsVertical(),
              ),
            ],
          ),
        ),

        // Bottom panel (form)
        _buildStep1BottomPanel(),
      ],
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.xs),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewBadge() {
    final isLive = _isLive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.liveRed.withValues(alpha: isLive ? 1.0 : 0.85),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, color: Colors.white, size: 8),
          const SizedBox(width: 4),
          Text(isLive ? 'LIVE' : 'PREVIEW',
            style: const TextStyle(color: Colors.white, fontSize: AppSizes.fontXs, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildUserLabel() {
    return Row(
      children: [
        const CircleAvatar(
          radius: 14,
          backgroundColor: AppColors.primary,
          child: Icon(Icons.person, color: Colors.white, size: 16),
        ),
        const SizedBox(width: AppSizes.xs),
        Text('Bạn',
          style: TextStyle(
            color: Colors.white,
            fontSize: AppSizes.fontSm,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(blurRadius: 4, color: Colors.black.withValues(alpha: 0.6))],
          ),
        ),
      ],
    );
  }

  Widget _buildCameraControlsVertical() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mic toggle — vị trí người dùng yêu cầu: cùng cột với camera controls
        _CameraIconBtn(
          icon: _isMicOn ? Icons.mic : Icons.mic_off,
          active: _isMicOn,
          activeColor: _isMicOn ? Colors.white : Colors.redAccent,
          onTap: () => setState(() => _isMicOn = !_isMicOn),
        ),
        const SizedBox(height: AppSizes.sm),
        _CameraIconBtn(
          icon: _isCameraOn ? Icons.videocam : Icons.videocam_off,
          active: _isCameraOn,
          onTap: () => setState(() => _isCameraOn = !_isCameraOn),
        ),
        const SizedBox(height: AppSizes.sm),
        _CameraIconBtn(
          icon: Icons.flip_camera_android,
          active: _cameras.length > 1,
          onTap: _cameras.length > 1 ? _flipCamera : null,
        ),
      ],
    );
  }

  Widget _buildStep1BottomPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSizes.sm),

            // Scrollable content
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: (MediaQuery.of(context).size.height * 0.45 -
                        MediaQuery.of(context).viewInsets.bottom)
                    .clamp(100.0, double.infinity),
              ),
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title field
                    TextFormField(
                      controller: _titleController,
                      maxLength: 60,
                      decoration: InputDecoration(
                        hintText: 'Nhập tiêu đề buổi live...',
                        hintStyle: const TextStyle(color: AppColors.textHint),
                        filled: true,
                        fillColor: AppColors.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                          borderSide: BorderSide.none,
                        ),
                        counterStyle: const TextStyle(color: AppColors.textHint, fontSize: 10),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.md, vertical: AppSizes.sm),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Vui lòng nhập tiêu đề';
                        if (v.trim().length < 5) return 'Tiêu đề phải có ít nhất 5 ký tự';
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSizes.sm),

                    // Category dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCategory,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: AppSizes.fontMd),
                          items: _categories
                              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                              .toList(),
                          onChanged: (v) { if (v != null) setState(() => _selectedCategory = v); },
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSizes.md),

                    // Products section
                    _buildProductsSection(),
                    const SizedBox(height: AppSizes.sm),

                    // Coupon section
                    _buildCouponSection(),
                    const SizedBox(height: AppSizes.md),
                  ],
                ),
              ),
            ),

            // TIẾP THEO button
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSizes.md, AppSizes.xs, AppSizes.md,
                AppSizes.md + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _goToStep2,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'TIẾP THEO',
                    style: TextStyle(fontSize: AppSizes.fontMd, fontWeight: FontWeight.w800, letterSpacing: 1),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Step 2: Confirm/start overlay ───────────────────────────────────────────

  Widget _buildStep2Overlay() {
    return _isLive ? _buildHostLiveOverlay() : _buildStep2PreLiveOverlay();
  }

  Widget _buildStep2PreLiveOverlay() {
    return Column(
      children: [
        // Top bar with back
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.xs),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                  onPressed: () => setState(() => _step = 1),
                ),
              ],
            ),
          ),
        ),

        Expanded(
          child: Stack(
            children: [
              Positioned(
                top: AppSizes.md,
                left: AppSizes.md,
                child: _buildPreviewBadge(),
              ),
              Positioned(
                bottom: AppSizes.md,
                left: AppSizes.md,
                child: _buildUserLabel(),
              ),
              if (_selectedProducts.isNotEmpty || _coupons.isNotEmpty)
                Positioned(
                  top: 48,
                  left: AppSizes.md,
                  // Stack a small column of product cards (cap at 3 visible so
                  // they don't cover the camera preview). The full list is
                  // still editable in step 1.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final p in _selectedProducts.take(3)) ...[
                        _buildProductDisplayCard(p),
                        const SizedBox(height: 6),
                      ],
                      if (_selectedProducts.length > 3) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                          ),
                          child: Text('+${_selectedProducts.length - 3} sản phẩm khác',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: AppSizes.fontXs,
                                fontWeight: FontWeight.w600,
                              )),
                        ),
                        const SizedBox(height: 6),
                      ],
                      // Coupon chips — show the host every coupon they've
                      // staged for the broadcast so they can sanity-check
                      // before tapping "Bắt đầu Livestream". Without this
                      // the preview only showed products and the host
                      // couldn't tell whether their LIVE25 coupon was
                      // actually attached.
                      for (final c in _coupons.take(3))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _buildCouponPreviewChip(c),
                        ),
                      if (_coupons.length > 3)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                          ),
                          child: Text('+${_coupons.length - 3} coupon khác',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: AppSizes.fontXs,
                                fontWeight: FontWeight.w600,
                              )),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        _buildStep2BottomPanel(),
      ],
    );
  }

  // ─── Host overlay (when actually broadcasting) ───────────────────────────────

  Widget _buildHostLiveOverlay() {
    final sid = _sessionId;
    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Top status bar
          Positioned(
            top: 0, left: 0, right: 0,
            child: _buildLiveTopBar(),
          ),
          // Chat overlay (left column, between the top bar and the pinned
          // product cards). The bottom is anchored above the product chips
          // (~bottom 250) so the "Chat người mua" header is never hidden,
          // even before any comment arrives.
          Positioned(
            left: 0,
            right: 96,
            top: 60,
            bottom: _selectedProducts.isEmpty ? 130 : 260,
            child: sid == null
                ? const SizedBox.shrink()
                : Consumer<LiveProvider>(
                    builder: (_, p, __) {
                      final s = p.currentStream;
                      final comments = (s != null && s.id == sid) ? s.comments : const <LiveComment>[];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Header chip
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                              ),
                              child: const Text(
                                'Chat người mua',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: AppSizes.fontXs,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSizes.xs),
                            // Chat body (LiveChatWidget shows its own
                            // "Chưa có tin nhắn nào" placeholder when empty)
                            Flexible(
                              child: LiveChatWidget(
                                comments: comments,
                                maxHeight: 380,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          // Right-side toolbar
          Positioned(
            right: AppSizes.sm,
            top: 60,
            bottom: 130,
            child: SingleChildScrollView(
              child: _buildHostSideToolbar(),
            ),
          ),
          // Floating pinned product list (left, just above the bottom panel)
          // — mirrors what the viewer sees, so the host knows which products
          // are currently highlighted.
          if (_selectedProducts.isNotEmpty)
            Positioned(
              left: AppSizes.sm,
              right: 96,
              bottom: 130,
              child: _buildHostFloatingProducts(),
            ),
          // Bottom stats + Kết thúc button
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _buildHostBottomPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveTopBar() {
    final mm = _liveElapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = _liveElapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(AppSizes.sm, AppSizes.xs, AppSizes.sm, AppSizes.md),
      child: Row(
        children: [
          GestureDetector(
            onTap: _confirmLeaveWhileLive,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 4),
          _buildPreviewBadge(),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _titleController.text.trim().isEmpty ? 'Live' : _titleController.text.trim(),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: AppSizes.fontSm, fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.access_time, color: Colors.white, size: 12),
                const SizedBox(width: 4),
                Text('$mm:$ss',
                    style: const TextStyle(color: Colors.white, fontSize: AppSizes.fontXs, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.visibility, color: Colors.white, size: 12),
                const SizedBox(width: 4),
                Text('$_statViewers',
                    style: const TextStyle(color: Colors.white, fontSize: AppSizes.fontXs, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostFloatingProducts() {
    // Show every pinned product as a small chip so the host can confirm
    // the list the viewer sees + unpin individual items mid-stream.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in _selectedProducts) ...[
          _HostPinnedProductChip(
            product: p,
            onRemove: () => _unpinProduct(p),
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  /// Remove a pinned product mid-stream. Talks to the backend so the
  /// server-side `live_session_products` row goes away too — viewers
  /// stop seeing it on next /products poll, and the DeepSeek bot won't
  /// match comments against it anymore.
  Future<void> _unpinProduct(LiveProduct p) async {
    final sid = _sessionId;
    // Optimistic local removal so the chip disappears immediately.
    setState(() => _selectedProducts.removeWhere((x) => x.id == p.id));
    if (sid == null) return; // pre-live: nothing to sync server-side yet
    try {
      await LiveRepository.instance.removeSessionProduct(sid, p.id);
    } catch (e) {
      AppLogger.logError(_tag, 'unpin product failed', e, null);
      if (!mounted) return;
      // Rollback so the host can retry — UI must reflect server state.
      setState(() => _selectedProducts.add(p));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không gỡ ghim được: $e')),
      );
    }
  }

  Widget _buildHostSideToolbar() {
    final items = <(IconData, String, VoidCallback?, bool)>[
      (_isMicOn ? Icons.mic : Icons.mic_off, 'Mic', () => setState(() => _isMicOn = !_isMicOn), false),
      (Icons.videocam, 'Cam', null, false),
      (Icons.flip_camera_android, 'Xoay', _cameras.length > 1 || _aliveController != null ? _flipCamera : null, false),
      (Icons.share, 'Chia sẻ', _onShare, false),
      // Live: open the pin manager sheet (highlight + add). Pre-live:
      // jump straight to the picker — pin only makes sense once we're
      // actually broadcasting, since the highlight is for current viewers.
      (Icons.push_pin_outlined, 'Ghim SP',
          _isLive ? _showHostPinSheet : _showAddProductSheet, false),
      // Pre-live: tap opens the create-coupon dialog (Action 1).
      // Mid-live: opens a manage sheet listing all live coupons with
      // "Phát coupon" so the host can re-announce one + a footer
      // button to create + auto-announce a new one (Action 4).
      (Icons.local_offer_outlined, 'Coupon',
          _isLive ? _showHostCouponSheet : _showAddCouponDialog, false),
      (Icons.smart_toy_outlined, _botEnabled ? 'Bot ON' : 'Bot AI',
          _botBusy ? null : _onToggleAiBot, _botEnabled),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final it in items) ...[
          _HostToolbarBtn(icon: it.$1, label: it.$2, onTap: it.$3, active: it.$4),
          const SizedBox(height: AppSizes.sm),
        ],
      ],
    );
  }

  Widget _buildHostBottomPanel() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSizes.md, AppSizes.md, AppSizes.md,
        AppSizes.sm + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _HostStat(icon: Icons.visibility_outlined, value: _statViewers, label: 'Người xem'),
              _HostStat(icon: Icons.shopping_cart_outlined, value: _statCartAdds, label: 'Giỏ hàng'),
              _HostStat(icon: Icons.person_add_alt_outlined, value: _statFollows, label: 'Theo dõi'),
              _HostStat(icon: Icons.favorite_outline, value: _statLikes, label: 'Thích'),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _stopLive,
              icon: const Icon(Icons.stop_circle_outlined, size: 20),
              label: const Text('Kết thúc Live',
                style: TextStyle(fontSize: AppSizes.fontMd, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.liveRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmLeaveWhileLive() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kết thúc buổi live?'),
        content: const Text('Người xem sẽ không thể xem tiếp. Bạn chắc chứ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Tiếp tục live')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kết thúc', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok == true) _stopLive();
  }

  void _onShare() {
    final sid = _sessionId;
    if (sid == null) return;
    Clipboard.setData(ClipboardData(text: 'tropia://live/$sid'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã copy link live')),
    );
  }

  Future<void> _onToggleAiBot() async {
    final sid = _sessionId;
    if (sid == null || _botBusy) return;
    final next = !_botEnabled;
    setState(() => _botBusy = true);
    try {
      final v = await LiveRepository.instance.setBotEnabled(sid, next);
      if (!mounted) return;
      setState(() {
        _botEnabled = v;
        _botBusy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          v ? 'Trợ lý AI đã BẬT — sẽ trả lời câu hỏi về sản phẩm'
            : 'Trợ lý AI đã TẮT')),
      );
    } catch (e) {
      AppLogger.logError(_tag, 'toggle bot failed', e, null);
      if (!mounted) return;
      setState(() => _botBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không đổi được trạng thái Bot: $e')),
      );
    }
  }

  Widget _buildProductImg(String url, double size) {
    final isLocal = !url.startsWith('http');
    if (isLocal) {
      return Image.file(
        File(url), width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size, height: size, color: AppColors.surfaceVariant,
          child: const Icon(Icons.image_outlined, size: 18, color: AppColors.textHint),
        ),
      );
    }
    return Image.network(
      url, width: size, height: size, fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: size, height: size, color: AppColors.surfaceVariant,
        child: const Icon(Icons.image_outlined, size: 18, color: AppColors.textHint),
      ),
    );
  }

  /// Tiny coupon chip rendered on the pre-live preview overlay so the
  /// host can see at a glance which coupons are queued for broadcast.
  /// Smaller than the chips in the bottom panel — preview is real
  /// estate-constrained because the camera feed is the focal point.
  Widget _buildCouponPreviewChip(_LiveCoupon c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.liveRed.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_offer, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(
            c.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: AppSizes.fontXs,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (c.minOrderValue > 0) ...[
            const SizedBox(width: 4),
            Text(
              '· đơn ${(c.minOrderValue / 1000).toInt()}K',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProductDisplayCard(LiveProduct product) {
    return Container(
      width: 120,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6)],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: _buildProductImg(product.imageUrl, 36),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.liveRed,
                    borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                  ),
                  child: const Text('Hiển thị',
                    style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2BottomPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: AppSizes.md),

          // Toolbar grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
            child: GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSizes.sm,
              crossAxisSpacing: AppSizes.xs,
              childAspectRatio: 1.1,
              children: _toolbarItems
                  .map((item) => _buildToolbarItem(item.$1, item.$2))
                  .toList(),
            ),
          ),

          const SizedBox(height: AppSizes.md),
          const Divider(height: 1),

          // Bottom action row
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSizes.md, AppSizes.sm, AppSizes.md,
              AppSizes.sm + MediaQuery.of(context).padding.bottom,
            ),
            child: _isLive ? _buildLiveActionRow() : _buildPreLiveActionRow(),
          ),
        ],
      ),
    );
  }

  Widget _buildPreLiveActionRow() {
    return Row(
      children: [
        // Quay lại button
        Expanded(
          child: OutlinedButton(
            onPressed: _isStarting ? null : () => setState(() => _step = 1),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.divider),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Quay lại',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppSizes.fontMd)),
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        // Bắt đầu Livestream button
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _isStarting ? null : _startLive,
            icon: _isStarting
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.live_tv, size: 18),
            label: Text(_isStarting ? 'Đang khởi động...' : 'Bắt đầu Livestream',
              style: const TextStyle(fontSize: AppSizes.fontMd, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.liveRed,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.liveRed.withValues(alpha: 0.6),
              disabledForegroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveActionRow() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _stopLive,
        icon: const Icon(Icons.stop_circle_outlined, size: 20),
        label: const Text('Dừng phát',
          style: TextStyle(fontSize: AppSizes.fontMd, fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.liveRed,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildToolbarItem(IconData icon, String label) {
    // "Hiệu ứng" is the one toolbar slot that's actually wired up — it
    // opens the face-sticker picker (tai thỏ / tai mèo). The rest stay
    // log-only placeholders for now; product wanted just the AR demo
    // for probation.
    final isStickerSlot = label == 'Hiệu ứng';
    final active = isStickerSlot && _faceSticker != FaceStickerKind.none;
    return GestureDetector(
      onTap: () {
        AppLogger.logUserEvent(
          action: 'toolbar_tapped',
          context: _tag,
          metadata: {'item': label},
        );
        if (isStickerSlot) _showFaceStickerSheet();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: active ? AppColors.primary : AppColors.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                color: active ? Colors.white : AppColors.textSecondary,
                size: 20),
          ),
          const SizedBox(height: 4),
          Text(
            active ? _faceSticker.label : label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              color: active ? AppColors.primary : AppColors.textSecondary,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFaceStickerSheet() async {
    final picked = await showModalBottomSheet<FaceStickerKind>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSizes.md, AppSizes.md,
                AppSizes.md, AppSizes.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Hiệu ứng khuôn mặt',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: AppSizes.fontMd,
                    )),
                const SizedBox(height: 4),
                const Text(
                  'Chỉ hiện trên màn hình của bạn — người xem không thấy.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: AppSizes.fontXs,
                  ),
                ),
                const SizedBox(height: AppSizes.md),
                Wrap(
                  spacing: AppSizes.sm,
                  runSpacing: AppSizes.sm,
                  children: FaceStickerKind.values.map((kind) {
                    final selected = kind == _faceSticker;
                    return GestureDetector(
                      onTap: () => Navigator.pop(sheetCtx, kind),
                      child: Container(
                        width: 72,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primaryContainer
                              : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                          border: Border.all(
                            color: selected
                                ? AppColors.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              kind == FaceStickerKind.none ? '🚫' : kind.glyph,
                              style: const TextStyle(fontSize: 28),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              kind.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _faceSticker = picked);
    }
  }

  // ─── Products section ─────────────────────────────────────────────────────────

  Widget _buildProductsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Product list (Shopee-style: image with overlay)
        if (_selectedProducts.isNotEmpty) ...[
          ...(_selectedProducts.asMap().entries.map((e) => _ProductSetupTile(
            product: e.value,
            index: e.key,
            onRemove: () => setState(() => _selectedProducts.removeAt(e.key)),
          ))),
          const SizedBox(height: AppSizes.xs),
        ],

        // "Thêm sản phẩm liên quan" button
        GestureDetector(
          onTap: _showAddProductSheet,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSizes.sm + 2),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              border: Border.all(color: AppColors.divider),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, color: AppColors.primary, size: 18),
                SizedBox(width: 6),
                Text(
                  'Thêm sản phẩm liên quan',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: AppSizes.fontSm,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Coupon section ───────────────────────────────────────────────────────────

  Widget _buildCouponSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Coupon chips list
        if (_coupons.isNotEmpty) ...[
          Wrap(
            spacing: AppSizes.xs,
            runSpacing: AppSizes.xs,
            children: _coupons.asMap().entries.map((e) {
              final c = e.value;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_offer, size: 12, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      c.label,
                      style: const TextStyle(
                        fontSize: AppSizes.fontXs,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => setState(() => _coupons.removeAt(e.key)),
                      child: const Icon(Icons.close, size: 12, color: AppColors.primary),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSizes.xs),
        ],

        // "Thêm coupon" button
        GestureDetector(
          onTap: _showAddCouponDialog,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSizes.sm + 2),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              border: Border.all(color: AppColors.divider),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.local_offer_outlined, color: AppColors.secondary, size: 18),
                SizedBox(width: 6),
                Text(
                  'Thêm coupon cho buổi live',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w600,
                    fontSize: AppSizes.fontSm,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddCouponDialog() async {
    if (_coupons.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tối đa 5 coupon mỗi buổi live')),
      );
      return;
    }
    final coupon = await showDialog<_LiveCoupon>(
      context: context,
      builder: (_) => const _CouponDialog(),
    );
    if (coupon != null && mounted) {
      setState(() => _coupons.add(coupon));
    }
  }

  Future<void> _showAddProductSheet() async {
    final result = await Navigator.push<List<LiveProduct>>(
      context,
      MaterialPageRoute(
        builder: (_) => SellerProductPickerScreen(
          alreadySelected: List.from(_selectedProducts),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _selectedProducts..clear()..addAll(result);
    });
    // If we're already live, push the new pinned set to the server so
    // viewers + the bot heuristic see the same list. Pre-live setup
    // skips this — products are bundled into the addSessionProducts call
    // that runs inside _startLive().
    final sid = _sessionId;
    if (sid == null || !_isLive) return;
    try {
      final created = await LiveRepository.instance.replaceSessionProducts(sid, [
        for (int i = 0; i < result.length; i++)
          {
            'product_id':     result[i].productId ?? result[i].id,
            'product_name':   result[i].name,
            'image_url':      result[i].imageUrl,
            'original_price': result[i].originalPrice,
            'sale_price':     result[i].salePrice,
            'discount_pct':   result[i].discountPercent,
            'stock_left':     result[i].stockLeft,
            'unit':           result[i].unit,
            'is_pinned':      i == 0,
          },
      ]);
      // Same id-swap dance as _startLive — backend assigns new
      // live_session_products.id rows on PUT, so we replace the local
      // list with the server-authoritative version. Otherwise pin/unpin
      // would hit catalog uuids and 404.
      if (created.isNotEmpty && mounted) {
        setState(() {
          _selectedProducts
            ..clear()
            ..addAll(created.map(_apiProductToLiveProduct));
        });
      }
    } catch (e) {
      AppLogger.logError(_tag, 'replace products failed', e, null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không cập nhật sản phẩm: $e')),
      );
    }
  }

  /// Shopee Live-style pin manager. Replaces the full-screen picker when
  /// the host taps "Ghim SP" mid-live — picker rebuilds the entire product
  /// set which is overkill for the common case (just spotlight one of the
  /// already-added products). Footer button still opens the full picker
  /// when the host needs to actually add new products to the session.
  Future<void> _showHostPinSheet() async {
    final sid = _sessionId;
    if (sid == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, sheetSetState) {
          return Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.push_pin, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Ghim sản phẩm đang giới thiệu',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 22),
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Nhấn "Gặp lên" để viewer thấy SP đang demo nổi bật.',
                  style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.55)),
                ),
                const SizedBox(height: 12),
                if (_selectedProducts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'Chưa có sản phẩm trong live.',
                        style: TextStyle(color: Colors.black.withValues(alpha: 0.5)),
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(sheetCtx).size.height * 0.5,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _selectedProducts.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = _selectedProducts[i];
                        final isPinned = _pinnedProductId == p.id;
                        return _PinSheetRow(
                          product: p,
                          isPinned: isPinned,
                          busy: _pinBusy,
                          onPin: () async {
                            await _setPin(sid, isPinned ? null : p.id);
                            sheetSetState(() {});
                          },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(sheetCtx).pop();
                    _showAddProductSheet();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Thêm sản phẩm mới vào live'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Map a `live_session_products` row (snake_case from the Go backend)
  /// into a LiveProduct. The crucial bit is that `id` here is the
  /// session-scoped uuid (live_session_products.id) — not the catalog
  /// product uuid — so subsequent pin / unpin / remove calls reference
  /// the right row.
  LiveProduct _apiProductToLiveProduct(Map<String, dynamic> row) {
    return LiveProduct(
      id:              row['id'] as String,
      productId:       row['product_id'] as String?,
      name:            (row['product_name'] ?? '') as String,
      imageUrl:        (row['image_url'] ?? '') as String,
      originalPrice:   (row['original_price'] as num? ?? 0).toDouble(),
      salePrice:       (row['sale_price']     as num? ?? 0).toDouble(),
      discountPercent: (row['discount_pct']   as num? ?? 0).toInt(),
      stockLeft:       (row['stock_left']     as num? ?? 0).toInt(),
      soldCount:       (row['sold_count']     as num? ?? 0).toInt(),
      unit:            (row['unit'] ?? 'cái') as String,
      category:        (row['category'] ?? '') as String,
    );
  }

  /// Toggle the highlight ("GẶP LÊN"). [productId] null clears the pin.
  /// Optimistic UI: flip local state immediately, rollback on server
  /// error — the WS stats event will reconcile within ~1 RTT anyway,
  /// but the optimistic path keeps the host's tap feedback instant.
  Future<void> _setPin(String sid, String? productId) async {
    if (_pinBusy) return;
    final previous = _pinnedProductId;
    setState(() {
      _pinBusy = true;
      _pinnedProductId = productId;
    });
    try {
      await LiveRepository.instance.setPinnedProduct(sid, productId);
    } catch (e) {
      AppLogger.logError(_tag, 'pin product failed', e, null);
      if (!mounted) return;
      setState(() => _pinnedProductId = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không ghim được: $e')),
      );
    } finally {
      if (mounted) setState(() => _pinBusy = false);
    }
  }

  /// Mid-live coupon manager. Shopee Live "Coupon" button: list every
  /// coupon the host has set up for this session with a "Phát coupon"
  /// button that re-broadcasts the floating banner to every viewer.
  /// Tạo coupon mới ở đây cũng auto-announce (backend side).
  Future<void> _showHostCouponSheet() async {
    final sid = _sessionId;
    if (sid == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, sheetSetState) {
          return Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.local_offer, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Coupon trong buổi live',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 22),
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Nhấn "Phát coupon" để banner hiện trên màn hình tất cả viewer.',
                  style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.55)),
                ),
                const SizedBox(height: 12),
                if (_coupons.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'Chưa có coupon nào.',
                        style: TextStyle(color: Colors.black.withValues(alpha: 0.5)),
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(sheetCtx).size.height * 0.45,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _coupons.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final c = _coupons[i];
                        return _CouponSheetRow(
                          coupon: c,
                          busy: _couponBusy,
                          onAnnounce: c.serverId == null
                              ? null
                              : () async {
                                  await _announceCoupon(sid, c.serverId!);
                                  sheetSetState(() {});
                                },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final coupon = await showDialog<_LiveCoupon>(
                      context: sheetCtx,
                      builder: (_) => const _CouponDialog(),
                    );
                    if (coupon == null) return;
                    setState(() => _coupons.add(coupon));
                    // Persist + auto-announce via backend.
                    await _persistCoupon(sid, coupon);
                    sheetSetState(() {});
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Tạo coupon mới (phát luôn)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Re-broadcasts an existing coupon to every viewer's floating banner.
  Future<void> _announceCoupon(String sid, String couponId) async {
    if (_couponBusy) return;
    setState(() => _couponBusy = true);
    try {
      await LiveRepository.instance.announceCoupon(sid, couponId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã phát coupon cho viewer')),
      );
    } catch (e) {
      AppLogger.logError(_tag, 'announce coupon failed', e, null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không phát được: $e')),
      );
    } finally {
      if (mounted) setState(() => _couponBusy = false);
    }
  }

  // ─── Navigation ───────────────────────────────────────────────────────────────

  void _goToStep2() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _step = 2);
    AppLogger.logUserEvent(
      action: 'live_setup_step2',
      context: _tag,
      metadata: {
        'title': _titleController.text.trim(),
        'category': _selectedCategory,
        'productCount': _selectedProducts.length,
      },
    );
  }

  Future<void> _startLive() async {
    if (_isStarting || _isLive) return;
    final title = _titleController.text.trim();

    AppLogger.logUserEvent(
      action: 'host_live_started',
      context: _tag,
      metadata: {
        'title': title,
        'category': _selectedCategory,
        'productCount': _selectedProducts.length,
      },
    );

    // 1. Request camera + mic permissions (apivideo_live_stream needs them).
    final camPerm = await Permission.camera.request();
    final micPerm = await Permission.microphone.request();
    if (!camPerm.isGranted || !micPerm.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cần quyền Camera & Microphone để livestream')),
      );
      return;
    }
    // Android 13+ requires runtime permission to post the ongoing
    // notification the foreground service relies on. Fire-and-forget:
    // if user denies, the service still starts (Android won't kill the
    // process for missing notification permission alone, just hide it),
    // so the stream stability win is preserved.
    await Permission.notification.request();

    setState(() => _isStarting = true);

    // 2. Create the stream session on the backend (returns RTMP/WHIP/SRT URLs).
    Map<String, dynamic> res;
    try {
      res = await LiveRepository.instance.startLive(
        title: title,
        category: _selectedCategory,
      );
    } catch (e) {
      AppLogger.logError(_tag, 'startLive backend failed', e, null);
      if (!mounted) return;
      setState(() => _isStarting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không tạo được stream: $e')),
      );
      return;
    }

    final session = res['session'] as Map<String, dynamic>?;
    final publishJson = res['publish'] as Map<String, dynamic>?;
    if (session == null || publishJson == null) {
      if (!mounted) return;
      setState(() => _isStarting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phản hồi từ server không hợp lệ')),
      );
      return;
    }

    // 2b. Attach picked products to the session so viewers see them.
    final newSessionId = session['id'] as String?;
    if (newSessionId != null && _selectedProducts.isNotEmpty) {
      try {
        final created = await LiveRepository.instance.addSessionProducts(
          newSessionId,
          [
            for (int i = 0; i < _selectedProducts.length; i++)
              {
                // Send `product_id` only if it looks like a real catalog uuid
                // (LiveProduct.id is `live_session_products.id` after the
                // session is materialized, but at setup time it's the real
                // product uuid from product picker).
                'product_id':     _selectedProducts[i].productId ?? _selectedProducts[i].id,
                'product_name':   _selectedProducts[i].name,
                'image_url':      _selectedProducts[i].imageUrl,
                'original_price': _selectedProducts[i].originalPrice,
                'sale_price':     _selectedProducts[i].salePrice,
                'discount_pct':   _selectedProducts[i].discountPercent,
                'stock_left':     _selectedProducts[i].stockLeft,
                'unit':           _selectedProducts[i].unit,
                'is_pinned':      i == 0, // first product pinned by default
              },
          ],
        );
        // Replace LiveProduct.id with the server-issued
        // live_session_products.id so pin/unpin/remove can reference the
        // session-scoped row. Without this, _selectedProducts[i].id is
        // still the catalog product uuid → backend can't find it →
        // pin POST returns 404 "product not in this session".
        if (created.isNotEmpty) {
          setState(() {
            _selectedProducts
              ..clear()
              ..addAll(created.map(_apiProductToLiveProduct));
          });
        }
      } catch (e) {
        AppLogger.logError(_tag, 'attach session products failed', e, null);
      }
    }
    final publish = PublishURLs.fromJson(publishJson);
    final rtmp = publish.rtmp;
    if (rtmp.isEmpty) {
      if (!mounted) return;
      setState(() => _isStarting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server không trả về RTMP URL')),
      );
      return;
    }

    // 3. Release package:camera so apivideo can claim the camera device.
    final old = _cameraController;
    _cameraController = null;
    if (mounted) setState(() => _cameraReady = false);
    await old?.dispose();
    await Future.delayed(const Duration(milliseconds: 300));

    // 4. Init the RTMP publisher and start streaming.
    try {
      // Mirror the package:camera choice (front/back) for a seamless preview.
      _alivePosition = _cameras.isNotEmpty &&
              _cameras[_cameraIndex].lensDirection == CameraLensDirection.front
          ? alive.CameraPosition.front
          : alive.CameraPosition.back;

      final ctrl = alive.ApiVideoLiveStreamController(
        initialAudioConfig: alive.AudioConfig(),
        // 720p @ 1.5 Mbps — cap bitrate well below the package default
        // (2 Mbps) so buyers on 3G / weak 4G can keep up. Above ~1.8 Mbps
        // mobile viewers stall every few seconds; below ~1 Mbps the
        // video looks blocky on a phone screen. 1.5 Mbps is the Shopee/
        // TikTok Live sweet spot for 720x1280 portrait at 30fps.
        initialVideoConfig: alive.VideoConfig(
          bitrate: 1500000,
          resolution: alive.Resolution.RESOLUTION_720,
          fps: 30,
        ),
        initialCameraPosition: _alivePosition,
        onError: (e) {
          AppLogger.logError(_tag, 'apivideo runtime error', e, null);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Lỗi stream: $e')),
            );
          }
        },
      );
      await ctrl.initialize();

      final (server, streamKey) = _parseRtmp(rtmp);
      if (streamKey.isEmpty) throw 'Stream key trống';
      // Anchor the process with a foreground service BEFORE starting
      // the RTMP push so even if startStreaming takes a few seconds to
      // connect, Android already considers us a foreground priority.
      await LiveForegroundService.start(
        title: title.isEmpty ? 'Đang livestream' : title,
      );
      await ctrl.startStreaming(streamKey: streamKey, url: server);

      if (!mounted) {
        await ctrl.dispose();
        await LiveForegroundService.stop();
        return;
      }
      final sid = session['id'] as String?;
      setState(() {
        _aliveController = ctrl;
        _sessionId = sid;
        _isLive = true;
        _isStarting = false;
        _rtmpServer = server;
        _rtmpStreamKey = streamKey;
        _liveStartedAt = DateTime.now();
        _liveElapsed = Duration.zero;
        _statViewers = 0;
        _statLikes = 0;
        _statCartAdds = 0;
        _statFollows = 0;
      });
      _startLiveTicker();
      if (sid != null) {
        // Reuse LiveProvider's chat polling so the host sees viewer
        // comments in real time (same code path as the buyer side).
        context.read<LiveProvider>().openStream(sid);
        _startStatsPolling(sid);

        // Persist any vouchers the host set up in step 1. Fire-and-forget —
        // if one POST fails (duplicate code, malformed expiry, etc.) we log
        // it and keep going so the broadcast itself isn't blocked.
        for (final coupon in _coupons) {
          unawaited(_persistCoupon(sid, coupon));
        }
      }
    } catch (e) {
      AppLogger.logError(_tag, 'apivideo start failed', e, null);
      // Best-effort: tell the backend the stream never went live so the
      // session isn't stuck in "scheduled" forever.
      final sid = session['id'] as String?;
      if (sid != null) {
        try { await LiveRepository.instance.endLive(sid); } catch (_) {}
      }
      if (!mounted) return;
      setState(() => _isStarting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không bật được camera: $e')),
      );
      // Restore the preview camera so the user can retry.
      _initCamera();
    }
  }

  Future<void> _stopLive() async {
    // Snapshot stats BEFORE we touch state, so the end-screen gets the
    // numbers from the last successful poll instead of zeros.
    final ctrl = _aliveController;
    final sid = _sessionId;
    final viewers = _statViewers;
    final likes = _statLikes;
    final cart = _statCartAdds;
    final follows = _statFollows;
    final title = _titleController.text.trim();

    // Stop timers + WS immediately so realtime callbacks don't race
    // with the navigation push.
    _liveTicker?.cancel();
    _statsSocket?.close();
    _statsSocket = null;

    // Stop the Android foreground service NOW (before navigation) so
    // the persistent "Đang livestream" notification disappears
    // immediately when the host taps "Kết thúc Live". If we wait until
    // after pushReplacement the MethodChannel invocation can be torn
    // down with the State, leaving the notification orphaned until the
    // user kills the app.
    // Fire-and-forget: native bridge swallows MissingPluginException so
    // this never throws, and we don't need the result.
    LiveForegroundService.stop();

    // Flip _isLive off BEFORE nulling the controller so the build() pass
    // that runs between here and pushReplacement renders the step-2
    // pre-live overlay (which doesn't need _aliveController) instead of
    // the host-live overlay (which calls _aliveController! and would
    // crash, blocking the navigation — that's why "Kết thúc Live" was
    // sometimes leaving the UI stuck on the live screen even though the
    // backend had already marked the session ended).
    if (mounted) {
      setState(() {
        _isLive = false;
        _aliveController = null;
      });
    } else {
      _aliveController = null;
    }

    // Navigate to summary. Use a microtask so the framework finishes any
    // in-flight build before pushReplacement re-enters the navigator.
    if (sid != null && mounted) {
      await Future<void>.delayed(Duration.zero);
      if (!mounted) {
        // Got unmounted while waiting — fall through to cleanup.
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => LiveEndScreen(
              title: title.isEmpty ? 'Buổi live' : title,
              sessionId: sid,
              peakViewers: viewers,
              totalLikes: likes,
              cartAddCount: cart,
              followCount: follows,
            ),
          ),
        );
        try {
          // ignore: use_build_context_synchronously
          Provider.of<LiveProvider>(context, listen: false).closeStream();
        } catch (_) {}
      }
    }

    // Hit the backend FIRST so live_sessions.status='ended' is committed
    // before we tear down the RTMP socket. Otherwise apivideo's built-in
    // retry can fire `on_publish` one more time during stopStreaming(),
    // which used to overwrite status back to 'live' — leaving buyers
    // stuck on a "live" UI long after the host left the page. Backend's
    // MarkLive() also now refuses to revive an ended row, but ordering
    // the call this way removes the race entirely.
    if (sid != null) {
      try { await LiveRepository.instance.endLive(sid); } catch (_) {}
    }
    try { await ctrl?.stopStreaming(); } catch (_) {}
    try { await ctrl?.dispose(); } catch (_) {}
    // Foreground service already stopped above (before navigation) to
    // ensure the notification disappears even if the State unmounts
    // mid-teardown.
    AppLogger.logUserEvent(
      action: 'host_live_stopped',
      context: _tag,
      metadata: {'sessionId': sid ?? ''},
    );

    // Edge case: no session id (e.g. apivideo failed before backend created
    // the session). Nothing to summarize — just pop back.
    if (sid == null && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _startLiveTicker() {
    _liveTicker?.cancel();
    _liveTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _liveStartedAt == null) return;
      setState(() => _liveElapsed = DateTime.now().difference(_liveStartedAt!));
    });
  }

  Future<void> _persistCoupon(String sid, _LiveCoupon c) async {
    try {
      final body = await LiveRepository.instance.createLiveCoupon(
        sessionId:     sid,
        code:          c.code,
        discountType:  c.isPercentage ? 'percent' : 'fixed',
        discountValue: c.discountValue,
        minOrderValue: c.minOrderValue,
        maxUses:       c.maxUses,
        expiresAt:     c.expiresAt,
      );
      // Backfill the server uuid so the host can later "Phát lại" this
      // coupon — the announce endpoint needs the coupon id.
      final id = body?['id'] as String?;
      if (id != null) c.serverId = id;
    } catch (e) {
      AppLogger.logError(_tag, 'persist coupon failed', e, null);
    }
  }

  void _startStatsPolling(String sid) {
    // One-shot REST fetch so the overlay shows something while the WS
    // is still handshaking. After that, every counter change is pushed.
    _bootstrapStatsOnce(sid);
    _statsSocket?.close();
    final sock = LiveSocket(sid);
    _statsSocket = sock;
    sock.events.listen((ev) {
      if (!mounted || ev.type != 'stats') return;
      final raw = ev.raw;
      if (raw['status'] == 'ended' && _isLive) {
        _stopLive();
        return;
      }
      setState(() {
        _statViewers  = (raw['viewer_count']   as num? ?? _statViewers).toInt();
        _statLikes    = (raw['like_count']     as num? ?? _statLikes).toInt();
        _statCartAdds = (raw['cart_add_count'] as num? ?? _statCartAdds).toInt();
        _statFollows  = (raw['follow_count']   as num? ?? _statFollows).toInt();
        // pinned_product_id is always present in the payload (nullable),
        // so we overwrite unconditionally — `??` would let the previous
        // pin linger after an unpin.
        _pinnedProductId = raw['pinned_product_id'] as String?;
      });
    });
    sock.connect();
  }

  Future<void> _bootstrapStatsOnce(String sid) async {
    if (!mounted) return;
    try {
      final stats = await LiveRepository.instance.fetchSessionStats(sid);
      if (!mounted) return;
      if (stats['status'] == 'ended' && _isLive) {
        await _stopLive();
        return;
      }
      setState(() {
        _statViewers  = (stats['viewer_count']   as num? ?? _statViewers).toInt();
        _statLikes    = (stats['like_count']     as num? ?? _statLikes).toInt();
        _statCartAdds = (stats['cart_add_count'] as num? ?? _statCartAdds).toInt();
        _statFollows  = (stats['follow_count']   as num? ?? _statFollows).toInt();
        _pinnedProductId = stats['pinned_product_id'] as String?;
      });
    } catch (_) {/* WS will catch up */}
  }

  /// Splits `rtmp://host:port/app/streamkey` into
  /// `(rtmp://host:port/app, streamkey)` — what apivideo_live_stream expects.
  (String, String) _parseRtmp(String rtmpUrl) {
    final uri = Uri.parse(rtmpUrl);
    final parts = uri.path.split('/').where((s) => s.isNotEmpty).toList();
    final app = parts.isNotEmpty ? '/${parts.first}' : '/live';
    final key = parts.length >= 2 ? parts.last : '';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return ('${uri.scheme}://${uri.host}$port$app', key);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Host overlay primitives
// ─────────────────────────────────────────────────────────────────────────────

class _HostToolbarBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  const _HostToolbarBtn({
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: active ? AppColors.primary : Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: onTap == null ? Colors.white38 : Colors.white, size: 20),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: active ? AppColors.primary : Colors.white.withValues(alpha: 0.85),
              fontSize: 10,
              fontWeight: FontWeight.w500,
              shadows: [Shadow(blurRadius: 3, color: Colors.black.withValues(alpha: 0.6))],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small floating chip showing a pinned product (thumbnail + name + price)
/// rendered in the host's live overlay so they know what the viewer sees.
class _HostPinnedProductChip extends StatelessWidget {
  final LiveProduct product;
  final VoidCallback? onRemove;
  const _HostPinnedProductChip({required this.product, this.onRemove});

  Widget _thumb(String url) {
    final isLocal = !url.startsWith('http');
    Widget img;
    if (isLocal) {
      img = Image.file(File(url), width: 32, height: 32, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox(width: 32, height: 32));
    } else {
      img = Image.network(url, width: 32, height: 32, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox(width: 32, height: 32));
    }
    return ClipRRect(borderRadius: BorderRadius.circular(4), child: img);
  }

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}tr';
    if (v >= 1000) return '${(v / 1000).toInt()}K';
    return v.toInt().toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4)],
      ),
      child: Row(
        children: [
          _thumb(product.imageUrl),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(product.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    )),
                Text('${_fmt(product.salePrice)}đ',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.secondary,
                    )),
              ],
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 14, color: AppColors.textHint),
            ),
          ),
        ],
      ),
    );
  }
}

class _HostStat extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;

  const _HostStat({required this.icon, required this.value, required this.label});

  String _fmt(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(height: 2),
        Text(_fmt(value),
            style: const TextStyle(color: Colors.white, fontSize: AppSizes.fontMd, fontWeight: FontWeight.w700)),
        Text(label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class _LiveCoupon {
  final String code;
  final double discountValue;
  final bool isPercentage;
  final double minOrderValue;
  final int? maxUses;
  final DateTime expiresAt;
  // Set after the coupon is POSTed to the backend (mid-live create, or
  // after _persistCoupon resolves for the pre-live batch). Needed for
  // the "Phát lại" re-announce call which references it by id.
  String? serverId;

  _LiveCoupon({
    required this.code,
    required this.discountValue,
    required this.isPercentage,
    required this.minOrderValue,
    required this.expiresAt,
    this.maxUses,
  });

  String get label {
    final discount = isPercentage
        ? '${discountValue.toInt()}%'
        : '${_fmt(discountValue)}đ';
    final limitSuffix = maxUses != null ? ' ×$maxUses' : '';
    return 'Giảm $discount$limitSuffix';
  }

  String toCode() => code;

  Map<String, dynamic> toMap() => {
    'code':          code,
    'discountValue': discountValue,
    'isPercentage':  isPercentage,
    'minOrderValue': minOrderValue,
    'expiresAt':     expiresAt.toUtc().toIso8601String(),
    if (maxUses != null) 'maxUses': maxUses,
  };

  static String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}tr';
    if (v >= 1000) return '${(v / 1000).toInt()}K';
    return v.toInt().toString();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Coupon creation dialog
// ─────────────────────────────────────────────────────────────────────────────

class _CouponDialog extends StatefulWidget {
  const _CouponDialog();

  @override
  State<_CouponDialog> createState() => _CouponDialogState();
}

class _CouponDialogState extends State<_CouponDialog> {
  final _codeCtrl     = TextEditingController();
  final _valueCtrl    = TextEditingController();
  final _minOrderCtrl = TextEditingController();
  final _maxUsesCtrl  = TextEditingController();
  final _formKey      = GlobalKey<FormState>();
  bool _isPercentage  = false;
  DateTime? _expiresAt;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _valueCtrl.dispose();
    _minOrderCtrl.dispose();
    _maxUsesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final now  = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_expiresAt ?? date.add(const Duration(hours: 23, minutes: 59))),
    );
    if (!mounted) return;
    setState(() {
      _expiresAt = time == null
          ? date.copyWith(hour: 23, minute: 59)
          : date.copyWith(hour: time.hour, minute: time.minute);
    });
  }

  String _fmtExpiry(DateTime dt) {
    final d = '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year}';
    final t = '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    return '$d $t';
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_expiresAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn ngày hết hạn')),
      );
      return;
    }
    final value    = double.tryParse(_valueCtrl.text.trim()) ?? 0;
    final minOrder = double.tryParse(_minOrderCtrl.text.trim()) ?? 0;
    final maxUses  = int.tryParse(_maxUsesCtrl.text.trim());
    if (_isPercentage && (value <= 0 || value > 100)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Giảm % phải từ 1–100')),
      );
      return;
    }
    Navigator.pop(
      context,
      _LiveCoupon(
        code:          _codeCtrl.text.trim().toUpperCase(),
        discountValue: value,
        isPercentage:  _isPercentage,
        minOrderValue: minOrder,
        maxUses:       maxUses,
        expiresAt:     _expiresAt!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tạo coupon live', style: TextStyle(fontWeight: FontWeight.w700)),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Coupon code
              TextFormField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Mã coupon (VD: LIVE20K)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Vui lòng nhập mã';
                  if (v.trim().length < 3) return 'Tối thiểu 3 ký tự';
                  return null;
                },
              ),
              const SizedBox(height: AppSizes.sm),

              // Discount type toggle
              Row(
                children: [
                  const Text('Loại giảm:', style: TextStyle(fontSize: AppSizes.fontSm)),
                  const SizedBox(width: AppSizes.sm),
                  _TypeChip(
                    label: 'VNĐ',
                    selected: !_isPercentage,
                    onTap: () => setState(() => _isPercentage = false),
                  ),
                  const SizedBox(width: AppSizes.xs),
                  _TypeChip(
                    label: '%',
                    selected: _isPercentage,
                    onTap: () => setState(() => _isPercentage = true),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.sm),

              // Discount value
              TextFormField(
                controller: _valueCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _isPercentage ? 'Giá trị giảm (%)' : 'Giá trị giảm (VNĐ)',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixText: _isPercentage ? '%' : 'đ',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Nhập giá trị giảm';
                  if (double.tryParse(v.trim()) == null) return 'Số không hợp lệ';
                  return null;
                },
              ),
              const SizedBox(height: AppSizes.sm),

              // Min order
              TextFormField(
                controller: _minOrderCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Đơn tối thiểu (VNĐ, để trống = không giới hạn)',
                  border: OutlineInputBorder(),
                  isDense: true,
                  suffixText: 'đ',
                ),
              ),
              const SizedBox(height: AppSizes.sm),

              // Max uses
              TextFormField(
                controller: _maxUsesCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số lượt dùng tối đa (để trống = không giới hạn)',
                  border: OutlineInputBorder(),
                  isDense: true,
                  suffixText: 'lượt',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final n = int.tryParse(v.trim());
                  if (n == null || n <= 0) return 'Phải là số nguyên dương';
                  return null;
                },
              ),
              const SizedBox(height: AppSizes.sm),

              // Expires at
              GestureDetector(
                onTap: _pickExpiry,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: _expiresAt == null ? AppColors.error : AppColors.divider),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 16,
                          color: _expiresAt == null ? AppColors.error : AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        _expiresAt == null ? 'Ngày hết hạn *' : _fmtExpiry(_expiresAt!),
                        style: TextStyle(
                          fontSize: AppSizes.fontSm,
                          color: _expiresAt == null ? AppColors.error : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.secondary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Tạo coupon'),
        ),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.secondary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppSizes.radiusFull),
          border: Border.all(color: selected ? AppColors.secondary : AppColors.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppSizes.fontXs,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private widgets
// ─────────────────────────────────────────────────────────────────────────────

class _CameraIconBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;
  final Color? activeColor;

  const _CameraIconBtn({
    required this.icon,
    required this.active,
    this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: active ? (activeColor ?? Colors.white) : Colors.white38,
          size: 20,
        ),
      ),
    );
  }
}

// Shopee-style product tile: thumbnail with name+description overlay, delete + drag icons
class _ProductSetupTile extends StatelessWidget {
  final LiveProduct product;
  final int index;
  final VoidCallback onRemove;

  const _ProductSetupTile({
    required this.product,
    required this.index,
    required this.onRemove,
  });

  Widget _buildProductImg(String url, double size) {
    final isLocal = !url.startsWith('http');
    if (isLocal) {
      return Image.file(
        File(url), width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size, height: size, color: AppColors.surfaceVariant,
          child: const Icon(Icons.image_outlined, size: 18, color: AppColors.textHint),
        ),
      );
    }
    return Image.network(
      url, width: size, height: size, fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: size, height: size, color: AppColors.surfaceVariant,
        child: const Icon(Icons.image_outlined, size: 18, color: AppColors.textHint),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.xs),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          // Thumbnail with name overlay
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(AppSizes.radiusMd)),
            child: Stack(
              children: [
                _buildProductImg(product.imageUrl, 72),
                // Dark gradient overlay
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xCC000000)],
                      ),
                    ),
                  ),
                ),
                // Product name on top of image
                Positioned(
                  bottom: 4, left: 4, right: 4,
                  child: Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: AppSizes.sm),

          // Price info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppSizes.fontSm,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _fmtPrice(product.salePrice),
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontSize: AppSizes.fontXs,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          // Actions: delete + reorder
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.drag_handle, color: AppColors.textHint, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtPrice(double price) {
    if (price >= 1000000) return '${(price / 1000000).toStringAsFixed(1)}tr đ';
    if (price >= 1000) return '${(price / 1000).toInt()}K đ';
    return '${price.toInt()}đ';
  }
}

/// One row in the pin manager bottom sheet. Shows a small thumb + name +
/// price, with a trailing "GẶP LÊN" / "Đang ghim" button. We disable the
/// button while `busy` so a rapid double-tap doesn't fire two POST /pin
/// in flight.
class _PinSheetRow extends StatelessWidget {
  final LiveProduct product;
  final bool isPinned;
  final bool busy;
  final VoidCallback onPin;
  const _PinSheetRow({
    required this.product,
    required this.isPinned,
    required this.busy,
    required this.onPin,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              product.imageUrl,
              width: 44, height: 44, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 44, height: 44, color: Colors.black12,
                child: const Icon(Icons.image_not_supported, size: 18, color: Colors.black38),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  '${product.salePrice.toInt()}đ',
                  style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: busy ? null : onPin,
            style: ElevatedButton.styleFrom(
              backgroundColor: isPinned ? Colors.black.withValues(alpha: 0.08) : AppColors.primary,
              foregroundColor: isPinned ? Colors.black87 : Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              isPinned ? 'Đang ghim' : 'Gặp lên',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row in the host coupon manager bottom sheet. Shows code + value
/// + min order + max-uses, with a trailing "Phát coupon" button that
/// re-broadcasts the floating banner. [onAnnounce] is null when the
/// coupon hasn't been persisted to the backend yet (pre-live coupon
/// during the window between dialog confirm and _persistCoupon
/// completing) — in that case we disable the button to avoid 404s.
class _CouponSheetRow extends StatelessWidget {
  final _LiveCoupon coupon;
  final bool busy;
  final VoidCallback? onAnnounce;
  const _CouponSheetRow({
    required this.coupon,
    required this.busy,
    required this.onAnnounce,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = coupon.minOrderValue > 0
        ? 'Đơn tối thiểu ${(coupon.minOrderValue / 1000).toInt()}K đ'
        : 'Áp dụng mọi đơn';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Icon(Icons.local_offer, color: AppColors.primary, size: 22),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  coupon.label,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  '${coupon.code} • $subtitle',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: (busy || onAnnounce == null) ? null : onAnnounce,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              disabledBackgroundColor: Colors.black12,
            ),
            child: Text(
              onAnnounce == null ? 'Đang lưu...' : 'Phát coupon',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
