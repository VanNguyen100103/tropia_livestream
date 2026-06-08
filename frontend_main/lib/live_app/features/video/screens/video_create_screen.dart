// =============================================================================
// video_create_screen.dart
// =============================================================================
// Màn "Tạo video" kiểu TikTok / Shopee Video: nền là CAMERA PREVIEW trực tiếp
// (giống live_setup_screen) thay vì 2 nút mở picker hệ thống.
//
// Luồng:
//   • Nút tròn giữa → quay video (tap để bắt đầu, tap lần nữa để dừng).
//   • Ô "Thư viện" góc phải → chọn video có sẵn (chính là "navigate3").
//   • Quay xong / chọn xong → mở [VideoEditScreen] (navigate4) để chỉnh sửa,
//     rồi mới sang [VideoPublishScreen] (navigate5) để thêm mô tả & đăng.
//
// Trả về VideoPost (qua Navigator.pop) khi đăng thành công để màn Live cập nhật
// feed ngay.
// =============================================================================

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/core/utils/logger.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/models/video_model.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/screens/video_edit_screen.dart';

const _tag = 'VideoCreateScreen';

class VideoCreateScreen extends StatefulWidget {
  const VideoCreateScreen({super.key});

  @override
  State<VideoCreateScreen> createState() => _VideoCreateScreenState();
}

class _VideoCreateScreenState extends State<VideoCreateScreen>
    with WidgetsBindingObserver {
  final _picker = ImagePicker();

  // ─── Camera (preview, package:camera) — giống live_setup_screen ─────────────
  List<CameraDescription> _cameras = [];
  CameraController? _cameraController;
  int _cameraIndex = 0;
  bool _cameraReady = false;
  bool _micGranted = false;
  String? _cameraError;

  // ─── Trạng thái quay ────────────────────────────────────────────────────────
  bool _isRecording = false;
  // Chặn double-tap khi đang điều hướng sang publish / mở thư viện.
  bool _busy = false;
  static const _maxDuration = Duration(minutes: 3);
  Timer? _recordTicker;
  Duration _recorded = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Đang điều hướng sang màn khác (publish/picker) thì giữ nguyên, để
    // _openEditor tự quản lý camera.
    if (_busy) return;
    if (state == AppLifecycleState.paused) {
      _recordTicker?.cancel();
      final ctrl = _cameraController;
      _cameraController = null;
      _isRecording = false;
      if (mounted) setState(() => _cameraReady = false);
      ctrl?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraController == null) _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordTicker?.cancel();
    final ctrl = _cameraController;
    _cameraController = null;
    ctrl?.dispose();
    super.dispose();
  }

  // ─── Camera lifecycle ─────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    try {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) {
        if (mounted) {
          setState(() => _cameraError = 'Cần quyền camera để quay video');
        }
        return;
      }
      // Mic là tuỳ chọn — nếu bị từ chối vẫn quay được (không tiếng).
      _micGranted = (await Permission.microphone.request()).isGranted;

      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = 'Không tìm thấy camera');
        return;
      }
      _cameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      if (_cameraIndex < 0) _cameraIndex = 0;
      await _startCamera(_cameraIndex);
    } catch (e) {
      AppLogger.logError(_tag, 'Camera init failed', e, null);
      if (mounted) {
        setState(() => _cameraError = 'Không thể khởi động camera: $e');
      }
    }
  }

  Future<void> _startCamera(int index) async {
    final old = _cameraController;
    if (old != null) {
      _cameraController = null;
      await old.dispose();
    }
    final ctrl = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: _micGranted,
    );
    _cameraController = ctrl;
    try {
      await ctrl.initialize();
      if (mounted) {
        setState(() {
          _cameraReady = true;
          _cameraError = null;
        });
      }
    } on CameraException catch (e) {
      AppLogger.logError(_tag, 'Camera start failed', e, null);
      if (mounted) {
        setState(() {
          _cameraReady = false;
          _cameraError = e.description ?? 'Lỗi camera';
        });
      }
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _isRecording) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    setState(() => _cameraReady = false);
    await _startCamera(_cameraIndex);
  }

  // ─── Quay video ────────────────────────────────────────────────────────────────

  Future<void> _toggleRecord() async {
    final ctrl = _cameraController;
    if (ctrl == null || !_cameraReady || _busy) return;
    if (_isRecording) {
      await _stopRecord();
    } else {
      try {
        await ctrl.startVideoRecording();
        if (!mounted) return;
        setState(() {
          _isRecording = true;
          _recorded = Duration.zero;
        });
        _recordTicker = Timer.periodic(const Duration(milliseconds: 100), (_) {
          if (!mounted || !_isRecording) return;
          setState(() => _recorded += const Duration(milliseconds: 100));
          if (_recorded >= _maxDuration) _stopRecord();
        });
      } catch (e) {
        AppLogger.logError(_tag, 'startVideoRecording failed', e, null);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Không thể quay: $e')));
        }
      }
    }
  }

  Future<void> _stopRecord() async {
    final ctrl = _cameraController;
    if (ctrl == null || !_isRecording) return;
    _recordTicker?.cancel();
    try {
      final file = await ctrl.stopVideoRecording();
      if (!mounted) return;
      setState(() => _isRecording = false);
      await _openEditor(file);
    } catch (e) {
      AppLogger.logError(_tag, 'stopVideoRecording failed', e, null);
      if (mounted) {
        setState(() => _isRecording = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Không lưu được video: $e')));
      }
    }
  }

  // ─── Thư viện (navigate3) ──────────────────────────────────────────────────────

  Future<void> _pickFromLibrary() async {
    if (_busy || _isRecording) return;
    setState(() => _busy = true);
    try {
      final file = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: _maxDuration,
      );
      if (file == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      await _openEditor(file);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể chọn video: $e')));
    }
  }

  /// Nhả camera, mở màn chỉnh sửa (navigate4). Nếu đăng thành công → trả
  /// VideoPost lên màn Live; nếu người dùng quay lại → khởi động lại camera để
  /// tiếp tục quay.
  Future<void> _openEditor(XFile file) async {
    if (!mounted) return;
    setState(() => _busy = true);
    // Nhả thiết bị camera trong lúc chỉnh/đăng (VideoEditScreen tự dựng
    // VideoPlayerController để preview) — tránh tranh chấp camera trên máy yếu.
    final ctrl = _cameraController;
    _cameraController = null;
    _cameraReady = false;
    await ctrl?.dispose();
    if (!mounted) return;

    final result = await Navigator.of(context).push<VideoPost>(
      MaterialPageRoute<VideoPost>(
        builder: (_) => VideoEditScreen(video: file),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(result); // đăng thành công → lên màn Live
      return;
    }
    // Quay lại màn quay → bật lại camera.
    setState(() => _busy = false);
    await _initCamera();
  }

  void _comingSoon(String label) {
    AppLogger.logUserEvent(
      action: 'video_create_tool_tapped',
      context: _tag,
      metadata: {'item': label},
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"$label" sắp ra mắt'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        // SizedBox.expand ép body chiếm trọn màn hình. Route này cấp cho
        // Scaffold body ràng buộc chiều cao "loose" (minHeight=0); nếu để Stack
        // trần, nó sẽ co lại bằng đúng chiều cao top bar (~210px) khiến toàn bộ
        // overlay dồn lên trên + tràn đáy. (live_setup_screen "thoát" vì overlay
        // của nó là Column full-height, tự kéo Stack cao bằng màn.)
        body: SizedBox.expand(
          child: Stack(
            children: [
              Positioned.fill(child: _buildCameraBackground()),
              // Lớp tối nhẹ ở trên/dưới để chữ trắng luôn đọc được.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.55),
                        ],
                        stops: const [0, 0.2, 0.65, 1],
                      ),
                    ),
                  ),
                ),
              ),
              _buildTopBar(),
              _buildSideTools(),
              _buildBottomControls(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Camera background (cover-fit, copy logic từ live_setup_screen) ─────────────

  Widget _buildCameraBackground() {
    if (_cameraError != null) return _buildCameraErrorBg();
    if (!_cameraReady || _cameraController == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white38)),
      );
    }
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
                  child: CameraPreview(ctrl),
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
              style: const TextStyle(
                color: Colors.white54,
                fontSize: AppSizes.fontSm,
              ),
            ),
            const SizedBox(height: AppSizes.md),
            TextButton(
              onPressed: _initCamera,
              child: const Text(
                'Thử lại',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            TextButton(
              onPressed: _pickFromLibrary,
              child: const Text(
                'Chọn từ thư viện',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Top bar: X · Thêm nhạc · lật camera ────────────────────────────────────────

  Widget _buildTopBar() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.sm,
          vertical: AppSizes.xs,
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 26),
              onPressed: _isRecording
                  ? null
                  : () => Navigator.of(context).pop(),
            ),
            const Spacer(),
            // "Thêm nhạc" pill — placeholder cho tới khi có module nhạc.
            GestureDetector(
              onTap: () => _comingSoon('Thêm nhạc'),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.md,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.music_note, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'Thêm nhạc',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: AppSizes.fontSm,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(
                Icons.cameraswitch_outlined,
                color: Colors.white,
                size: 24,
              ),
              onPressed: _cameras.length > 1 ? _flipCamera : null,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Side tools (Làm đẹp / Bộ lọc / Hẹn giờ / Tốc độ) — placeholders ───────────

  Widget _buildSideTools() {
    if (_isRecording) return const SizedBox.shrink();
    return Positioned(
      top: 0,
      bottom: 0,
      right: AppSizes.sm,
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _SideTool(
              icon: Icons.face_retouching_natural,
              label: 'Làm đẹp',
              onTap: () => _comingSoon('Làm đẹp'),
            ),
            const SizedBox(height: AppSizes.lg),
            _SideTool(
              icon: Icons.blur_on,
              label: 'Bộ lọc',
              onTap: () => _comingSoon('Bộ lọc'),
            ),
            const SizedBox(height: AppSizes.lg),
            _SideTool(
              icon: Icons.timer_outlined,
              label: 'Hẹn giờ',
              onTap: () => _comingSoon('Hẹn giờ'),
            ),
            const SizedBox(height: AppSizes.lg),
            _SideTool(
              icon: Icons.speed,
              label: 'Tốc độ',
              onTap: () => _comingSoon('Tốc độ'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Bottom: Hiệu ứng · nút quay · Thư viện + tab Hình ảnh/Video/Mẫu ────────────

  Widget _buildBottomControls() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isRecording) ...[
              _buildRecordTimer(),
              const SizedBox(height: AppSizes.sm),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Hiệu ứng (trái)
                  _isRecording
                      ? const SizedBox(width: 64)
                      : _SideTool(
                          icon: Icons.auto_awesome,
                          label: 'Hiệu ứng',
                          onTap: () => _comingSoon('Hiệu ứng'),
                        ),
                  // Nút quay (giữa)
                  _buildRecordButton(),
                  // Thư viện (phải) — chính là "navigate3"
                  _isRecording
                      ? const SizedBox(width: 64)
                      : _buildLibraryButton(),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.md),
            if (!_isRecording) _buildModeTabs(),
            const SizedBox(height: AppSizes.sm),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordTimer() {
    final s = _recorded.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.liveRed,
        borderRadius: BorderRadius.circular(AppSizes.radiusFull),
      ),
      child: Text(
        '$mm:$ss',
        style: const TextStyle(
          color: Colors.white,
          fontSize: AppSizes.fontSm,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildRecordButton() {
    final progress = _isRecording
        ? (_recorded.inMilliseconds / _maxDuration.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    return GestureDetector(
      onTap: _busy ? null : _toggleRecord,
      child: SizedBox(
        width: 84,
        height: 84,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 5),
              ),
            ),
            if (_isRecording)
              SizedBox(
                width: 84,
                height: 84,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 5,
                  color: AppColors.secondary,
                  backgroundColor: Colors.transparent,
                ),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _isRecording ? 30 : 66,
              height: _isRecording ? 30 : 66,
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(_isRecording ? 8 : 33),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryButton() {
    return GestureDetector(
      onTap: _busy ? null : _pickFromLibrary,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: _busy
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.photo_library_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Thư viện',
            style: TextStyle(
              color: Colors.white,
              fontSize: AppSizes.fontXs,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTabs() {
    Widget tab(String label, {bool active = false, VoidCallback? onTap}) {
      return GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white60,
                  fontSize: AppSizes.fontMd,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 18,
                height: 2,
                color: active ? AppColors.secondary : Colors.transparent,
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        tab('Hình ảnh', onTap: () => _comingSoon('Chụp ảnh')),
        tab('Video', active: true),
        tab('Mẫu', onTap: () => _comingSoon('Mẫu')),
      ],
    );
  }
}

// ─── Helper: nút công cụ dạng icon + nhãn ─────────────────────────────────────────

class _SideTool extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SideTool({
    required this.icon,
    required this.label,
    required this.onTap,
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
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: AppSizes.fontXs,
              fontWeight: FontWeight.w600,
              shadows: [
                Shadow(
                  blurRadius: 4,
                  color: Colors.black.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
