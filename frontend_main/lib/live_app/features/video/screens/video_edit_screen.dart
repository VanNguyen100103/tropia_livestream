// =============================================================================
// video_edit_screen.dart  ("navigate4")
// =============================================================================
// Màn CHỈNH SỬA video kiểu TikTok / Shopee Video — bước nằm GIỮA màn quay/chọn
// video ([VideoCreateScreen] = "navigate2/3") và màn đăng
// ([VideoPublishScreen] = "navigate5").
//
// Luồng:
//   quay / chọn thư viện  →  VideoEditScreen (preview + công cụ)  →  "Tiếp theo"
//   →  VideoPublishScreen (Thêm mô tả & đăng).
//
// Nền là video preview lặp (VideoPlayerController.file). Các công cụ (Thêm nhạc,
// Cắt video, Văn bản, Nhãn dán, Lồng tiếng, Bộ lọc, Hiệu ứng...) hiện là
// placeholder ("sắp ra mắt") — đồng bộ với cách [VideoCreateScreen] stub công cụ
// bằng SnackBar cho tới khi có module xử lý video.
//
// Trả VideoPost (qua Navigator.pop) khi đăng thành công — bong bóng lên màn Live
// để feed cập nhật ngay; nếu người dùng quay lại từ màn đăng thì ở lại đây.
// =============================================================================

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/core/utils/logger.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/models/video_model.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/screens/video_publish_screen.dart';

const _tag = 'VideoEditScreen';

class VideoEditScreen extends StatefulWidget {
  final XFile video;
  const VideoEditScreen({super.key, required this.video});

  @override
  State<VideoEditScreen> createState() => _VideoEditScreenState();
}

class _VideoEditScreenState extends State<VideoEditScreen> {
  VideoPlayerController? _preview;
  // Chặn double-tap khi đang điều hướng sang màn đăng.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initPreview();
  }

  Future<void> _initPreview() async {
    if (kIsWeb) return; // file:// preview chỉ chạy trên mobile/desktop
    try {
      final ctrl = VideoPlayerController.file(File(widget.video.path));
      _preview = ctrl;
      await ctrl.initialize();
      await ctrl.setLooping(true);
      await ctrl.play();
      if (mounted) setState(() {});
    } catch (_) {
      _preview = null;
    }
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _preview;
    if (c == null || !c.value.isInitialized) return;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
  }

  void _comingSoon(String label) {
    AppLogger.logUserEvent(
      action: 'video_edit_tool_tapped',
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

  /// "Tiếp theo" → mở [VideoPublishScreen]. Nếu đăng thành công nó trả VideoPost
  /// → bong bóng tiếp lên màn Live; nếu quay lại → tiếp tục chỉnh ở đây.
  Future<void> _next() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _preview?.pause(); // nhường preview cho VideoPublishScreen
    if (!mounted) return;

    final post = await Navigator.of(context).push<VideoPost>(
      MaterialPageRoute<VideoPost>(
        builder: (_) => VideoPublishScreen(video: widget.video),
      ),
    );
    if (!mounted) return;
    if (post != null) {
      Navigator.of(context).pop(post); // đăng xong → lên màn Live
      return;
    }
    setState(() => _busy = false);
    await _preview?.play();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildPreview(),
            _buildTopBar(),
            _buildSideTools(),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // ─── Preview video (nền) ────────────────────────────────────────────────────
  Widget _buildPreview() {
    final c = _preview;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: c.value.size.width,
              height: c.value.size.height,
              child: VideoPlayer(c),
            ),
          ),
          if (!c.value.isPlaying)
            const Center(
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white70,
                size: 72,
              ),
            ),
        ],
      ),
    );
  }

  // ─── Top bar: ‹ · Thêm nhạc ─────────────────────────────────────────────────
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
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
            ),
            const Spacer(),
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
            const SizedBox(width: 48), // cân đối với IconButton bên trái
          ],
        ),
      ),
    );
  }

  // ─── Công cụ bên phải (Hiệu ứng âm thanh / Bộ lọc / Hiệu ứng / Cải thiện) ────
  Widget _buildSideTools() {
    return Positioned(
      top: 0,
      bottom: 0,
      right: AppSizes.sm,
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _EditTool(
              icon: Icons.graphic_eq,
              label: 'Hiệu ứng\nâm thanh',
              onTap: () => _comingSoon('Hiệu ứng âm thanh'),
            ),
            const SizedBox(height: AppSizes.lg),
            _EditTool(
              icon: Icons.lens_blur,
              label: 'Bộ lọc',
              onTap: () => _comingSoon('Bộ lọc'),
            ),
            const SizedBox(height: AppSizes.lg),
            _EditTool(
              icon: Icons.auto_awesome,
              label: 'Hiệu ứng',
              onTap: () => _comingSoon('Hiệu ứng'),
            ),
            const SizedBox(height: AppSizes.lg),
            _EditTool(
              icon: Icons.auto_fix_high,
              label: 'Cải thiện',
              onTap: () => _comingSoon('Cải thiện'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Thanh dưới: Cắt video · Văn bản · Nhãn dán · Lồng tiếng + Tiếp theo ─────
  Widget _buildBottomBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.md,
            vertical: AppSizes.sm,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.55),
              ],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _EditTool(
                      icon: Icons.content_cut,
                      label: 'Cắt video',
                      onTap: () => _comingSoon('Cắt video'),
                    ),
                    _EditTool(
                      icon: Icons.text_fields,
                      label: 'Văn bản',
                      onTap: () => _comingSoon('Văn bản'),
                    ),
                    _EditTool(
                      icon: Icons.emoji_emotions_outlined,
                      label: 'Nhãn dán',
                      onTap: () => _comingSoon('Nhãn dán'),
                    ),
                    _EditTool(
                      icon: Icons.mic_none,
                      label: 'Lồng tiếng',
                      onTap: () => _comingSoon('Lồng tiếng'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.md),
              _buildNextButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNextButton() {
    return GestureDetector(
      onTap: _busy ? null : _next,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.lg,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: AppColors.secondary,
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        ),
        child: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Tiếp theo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppSizes.fontMd,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

// ─── Helper: nút công cụ icon + nhãn (đồng bộ _SideTool của VideoCreateScreen) ──
class _EditTool extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _EditTool({
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
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: AppSizes.fontXs,
              fontWeight: FontWeight.w600,
              height: 1.1,
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
