// =============================================================================
// video_share_sheet.dart  ("navigate10")
// =============================================================================
// Bottom sheet "Chia sẻ với Bạn bè và Gia đình!" kiểu Shopee Video / TikTok.
// Mở khi nhấn nút "..." (Xem thêm) trên action rail của 1 video.
//
//   - Hàng 1 (cuộn ngang): các app chia sẻ (Messenger, Zalo, WhatsApp,
//     Facebook, Telegram, Instagram, Line, Twitter...). Chạm → mở hộp chia sẻ
//     hệ thống (share_plus) với link video — vì app chưa deep-link riêng từng
//     mạng xã hội.
//   - Hàng 2 (cuộn ngang): thao tác (Sao chép đường dẫn, Lưu, Ghim, Duet,
//     Phản hồi, Sao chép thông tin, Email, SMS, và Xóa nếu là video của mình).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/data/video_repository.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/models/video_model.dart';

/// Mở share sheet cho [video]. [onShared] chạy sau khi người dùng chia sẻ thành
/// công (để cộng share count). [isOwner] = true sẽ hiện thêm nút "Xóa";
/// [onDeleted] chạy sau khi xóa video thành công (để màn cha gỡ khỏi danh sách).
Future<void> showVideoShareSheet(
  BuildContext context, {
  required VideoPost video,
  VoidCallback? onShared,
  VoidCallback? onDeleted,
  bool isOwner = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppSizes.radiusXl)),
    ),
    builder: (_) => _VideoShareSheet(
      video: video,
      onShared: onShared,
      onDeleted: onDeleted,
      isOwner: isOwner,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _SocialTarget {
  final String label;
  final Color color;
  final IconData? icon;
  final String? text; // fallback chữ khi không có icon thương hiệu phù hợp
  const _SocialTarget(this.label, this.color, {this.icon, this.text});
}

class _ShareAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  const _ShareAction(this.label, this.icon, this.onTap, {this.enabled = true});
}

class _VideoShareSheet extends StatelessWidget {
  final VideoPost video;
  final VoidCallback? onShared;
  final VoidCallback? onDeleted;
  final bool isOwner;

  const _VideoShareSheet({
    required this.video,
    required this.onShared,
    required this.onDeleted,
    required this.isOwner,
  });

  String get _shareText {
    final caption = (video.caption?.isNotEmpty ?? false) ? '\n${video.caption}' : '';
    // shareUrl = bản đã bake overlay (fallback clip thô) → người mở link ngoài
    // app thấy thông tin burn sẵn trên video, không phải clip trần.
    return 'Xem video của @${video.displayName} trên Tropia$caption\n${video.shareUrl}';
  }

  Future<void> _shareNative(BuildContext context) async {
    Navigator.pop(context);
    await Share.share(_shareText);
    onShared?.call();
  }

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: video.shareUrl));
    if (!context.mounted) return;
    Navigator.pop(context);
    _toast(context, 'Đã sao chép đường dẫn');
  }

  Future<void> _copyInfo(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _shareText));
    if (!context.mounted) return;
    Navigator.pop(context);
    _toast(context, 'Đã sao chép thông tin video');
  }

  void _soon(BuildContext context) {
    Navigator.pop(context);
    _toast(context, 'Tính năng sắp ra mắt');
  }

  /// Xác nhận rồi gọi API xóa video. Thành công → đóng sheet + [onDeleted] để
  /// màn cha gỡ khỏi danh sách. Lỗi → giữ sheet, hiện thông báo.
  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Xóa video'),
        content: const Text(
          'Bạn có chắc muốn xóa video này? Hành động không thể hoàn tác.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text(
              'Hủy',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text(
              'Xóa',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await VideoRepository().deleteVideo(video.id);
    } catch (e) {
      if (context.mounted) _toast(context, AuthService.errorMessage(e));
      return;
    }
    if (!context.mounted) return;
    Navigator.pop(context); // đóng share sheet
    onDeleted?.call();
    _toast(context, 'Đã xóa video');
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Tất cả mạng xã hội đều fallback về hộp chia sẻ hệ thống với link video.
    final socials = <_SocialTarget>[
      const _SocialTarget('Messenger', Color(0xFF0084FF), icon: Icons.messenger),
      const _SocialTarget('Tin nhắn', Color(0xFF0068FF), text: 'Zalo'),
      const _SocialTarget('WhatsApp', Color(0xFF25D366), icon: Icons.chat),
      const _SocialTarget('Facebook', Color(0xFF1877F2), icon: Icons.facebook),
      const _SocialTarget('Nhật ký', Color(0xFF0068FF), text: 'Zalo'),
      const _SocialTarget('Feed', Color(0xFFE1306C), icon: Icons.camera_alt),
      const _SocialTarget('Telegram', Color(0xFF229ED9), icon: Icons.send),
      const _SocialTarget('Story', Color(0xFFE1306C), icon: Icons.add_a_photo),
      const _SocialTarget('Line', Color(0xFF06C755), text: 'LINE'),
      const _SocialTarget('Twitter', Color(0xFF1DA1F2), icon: Icons.alternate_email),
    ];

    final actions = <_ShareAction>[
      _ShareAction('Sao chép đường dẫn', Icons.link, () => _copyLink(context)),
      _ShareAction('Lưu', Icons.file_download_outlined, () => _soon(context)),
      _ShareAction('Ghim', Icons.push_pin_outlined, () => _soon(context)),
      _ShareAction('Duet', Icons.dynamic_feed, () => _soon(context), enabled: false),
      _ShareAction('Phản hồi', Icons.chat_bubble_outline, () => _soon(context)),
      _ShareAction('Sao chép thông tin', Icons.content_copy, () => _copyInfo(context)),
      _ShareAction('Email', Icons.mail_outline, () => _shareNative(context)),
      _ShareAction('SMS', Icons.sms_outlined, () => _shareNative(context)),
      if (isOwner)
        _ShareAction('Xóa', Icons.delete_outline, () => _confirmDelete(context)),
    ];

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSizes.sm),
          // Tiêu đề + nút đóng
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.md,
              AppSizes.sm,
              AppSizes.sm,
              AppSizes.sm,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Chia sẻ với Bạn bè và Gia đình!',
                    style: TextStyle(
                      fontSize: AppSizes.fontLg,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          // Hàng app chia sẻ (cuộn ngang)
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
              itemCount: socials.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSizes.lg),
              itemBuilder: (_, i) => _SocialButton(
                target: socials[i],
                onTap: () => _shareNative(context),
              ),
            ),
          ),
          const Divider(height: AppSizes.lg, indent: AppSizes.md, endIndent: AppSizes.md),
          // Hàng thao tác (cuộn ngang)
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
              itemCount: actions.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSizes.lg),
              itemBuilder: (_, i) => _ActionButton(action: actions[i]),
            ),
          ),
          const SizedBox(height: AppSizes.md),
        ],
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final _SocialTarget target;
  final VoidCallback onTap;
  const _SocialButton({required this.target, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(color: target.color, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: target.icon != null
                  ? Icon(target.icon, color: Colors.white, size: 28)
                  : Text(
                      target.text ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: AppSizes.fontSm,
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              target.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: AppSizes.fontXs,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final _ShareAction action;
  const _ActionButton({required this.action});

  @override
  Widget build(BuildContext context) {
    final fg = action.enabled ? AppColors.textPrimary : AppColors.textHint;
    return GestureDetector(
      onTap: action.enabled ? action.onTap : null,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.divider),
              ),
              alignment: Alignment.center,
              child: Icon(action.icon, color: fg, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              action.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppSizes.fontXs, color: fg, height: 1.1),
            ),
          ],
        ),
      ),
    );
  }
}
