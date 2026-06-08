// =============================================================================
// video_reports_admin_screen.dart
// =============================================================================
// Hàng đợi kiểm duyệt (admin): danh sách báo cáo pending → Gỡ video / Bỏ qua.
// Chỉ admin mới vào được (entry point ẩn theo role; backend cũng chặn bằng adminMw).
// =============================================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/data/video_repository.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/models/video_model.dart';

class VideoReportsAdminScreen extends StatefulWidget {
  const VideoReportsAdminScreen({super.key});

  @override
  State<VideoReportsAdminScreen> createState() =>
      _VideoReportsAdminScreenState();
}

class _VideoReportsAdminScreenState extends State<VideoReportsAdminScreen> {
  final _repo = VideoRepository();
  List<VideoReport> _reports = [];
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.fetchReports(status: 'pending');
      if (mounted) setState(() => _reports = list);
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolve(VideoReport r, bool takedown) async {
    if (_busy.contains(r.id)) return;
    setState(() => _busy.add(r.id));
    try {
      await _repo.resolveReport(r.id, takedown: takedown);
      if (mounted) {
        setState(() => _reports.removeWhere((x) => x.id == r.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(takedown ? 'Đã gỡ video' : 'Đã bỏ qua báo cáo'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AuthService.errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0.5,
        title: const Text('Kiểm duyệt video'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _error != null
          ? _ErrorView(message: _error!, onRetry: _load)
          : _reports.isEmpty
          ? const _EmptyView()
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(AppSizes.md),
                itemCount: _reports.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSizes.sm),
                itemBuilder: (_, i) => _ReportCard(
                  report: _reports[i],
                  busy: _busy.contains(_reports[i].id),
                  onTakedown: () => _resolve(_reports[i], true),
                  onDismiss: () => _resolve(_reports[i], false),
                ),
              ),
            ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final VideoReport report;
  final bool busy;
  final VoidCallback onTakedown;
  final VoidCallback onDismiss;

  const _ReportCard({
    required this.report,
    required this.busy,
    required this.onTakedown,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final thumb = report.thumbUrl;
    final removed = report.videoStatus == 'deleted';
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                child: SizedBox(
                  width: 56,
                  height: 74,
                  child: thumb != null
                      ? CachedNetworkImage(
                          imageUrl: thumb,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _thumbFallback(),
                        )
                      : _thumbFallback(),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.videoCaption?.isNotEmpty == true
                          ? report.videoCaption!
                          : '(không có mô tả)',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Người đăng: ${report.ownerName ?? "—"}',
                      style: const TextStyle(
                        fontSize: AppSizes.fontSm,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      'Người báo cáo: ${report.reporterName ?? "—"}',
                      style: const TextStyle(
                        fontSize: AppSizes.fontSm,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (removed)
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text(
                          'Video đã bị gỡ',
                          style: TextStyle(
                            fontSize: AppSizes.fontXs,
                            color: AppColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSizes.sm),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            ),
            child: Text(
              'Lý do: ${report.reason}',
              style: const TextStyle(fontSize: AppSizes.fontSm),
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: busy ? null : onDismiss,
                child: const Text(
                  'Bỏ qua',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              FilledButton.icon(
                onPressed: busy || removed ? null : onTakedown,
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete_outline, size: 18),
                label: const Text('Gỡ video'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _thumbFallback() => Container(
    color: Colors.black87,
    alignment: Alignment.center,
    child: const Icon(
      Icons.play_circle_outline,
      color: Colors.white30,
      size: 24,
    ),
  );
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.verified_outlined,
            size: AppSizes.iconXl,
            color: AppColors.textHint,
          ),
          SizedBox(height: AppSizes.md),
          Text(
            'Không có báo cáo nào',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: AppSizes.xs),
          Text(
            'Hàng đợi kiểm duyệt đang trống',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppSizes.fontSm,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: AppSizes.iconXl,
            color: AppColors.textHint,
          ),
          const SizedBox(height: AppSizes.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.xl),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          FilledButton.icon(
            onPressed: onRetry,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }
}
