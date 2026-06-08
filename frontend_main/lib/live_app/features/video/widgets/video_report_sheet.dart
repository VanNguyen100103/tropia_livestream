// =============================================================================
// video_report_sheet.dart
// =============================================================================
// Bottom sheet "Báo cáo" video: chọn lý do → gửi. Yêu cầu đăng nhập.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/data/video_repository.dart';

const _reasons = <String>[
  'Nội dung phản cảm',
  'Spam hoặc lừa đảo',
  'Vi phạm bản quyền',
  'Thông tin sai sự thật',
  'Khác',
];

/// Mở sheet báo cáo cho [videoId].
Future<void> showVideoReportSheet(
  BuildContext context, {
  required String videoId,
}) {
  if (!AuthService.instance.isSignedIn) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đăng nhập để báo cáo video')));
    return Future.value();
  }
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSizes.radiusXl),
      ),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSizes.sm),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(AppSizes.md),
            child: Text(
              'Báo cáo video',
              style: TextStyle(
                fontSize: AppSizes.fontLg,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Divider(height: 1),
          ..._reasons.map(
            (r) => ListTile(
              title: Text(r),
              trailing: const Icon(
                Icons.chevron_right,
                color: AppColors.textHint,
              ),
              onTap: () async {
                Navigator.pop(sheetCtx);
                try {
                  await VideoRepository().reportVideo(videoId, r);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Đã gửi báo cáo. Cảm ơn bạn!'),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(AuthService.errorMessage(e))),
                    );
                  }
                }
              },
            ),
          ),
          const SizedBox(height: AppSizes.sm),
        ],
      ),
    ),
  );
}
