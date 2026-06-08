// =============================================================================
// video_comment_sheet.dart
// =============================================================================
// Bottom sheet bình luận cho 1 video: danh sách comment + ô nhập "Thêm bình luận".
// =============================================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/data/video_repository.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/models/video_model.dart';

/// Mở sheet bình luận cho [videoId]. Truyền [video] để ghim caption của video
/// làm bình luận đầu tiên của tác giả (badge "Tác giả"), giống Shopee Video /
/// TikTok. Gọi [onAdded] khi gửi thành công (để màn feed tăng comment_count).
Future<void> showVideoCommentSheet(
  BuildContext context, {
  required String videoId,
  required int commentCount,
  VideoPost? video,
  VoidCallback? onAdded,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _VideoCommentSheet(
      videoId: videoId,
      commentCount: commentCount,
      video: video,
      onAdded: onAdded,
    ),
  );
}

class _VideoCommentSheet extends StatefulWidget {
  final String videoId;
  final int commentCount;
  final VideoPost? video;
  final VoidCallback? onAdded;

  const _VideoCommentSheet({
    required this.videoId,
    required this.commentCount,
    this.video,
    this.onAdded,
  });

  @override
  State<_VideoCommentSheet> createState() => _VideoCommentSheetState();
}

class _VideoCommentSheetState extends State<_VideoCommentSheet> {
  final _repo = VideoRepository();
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  List<VideoComment> _comments = [];
  bool _loading = true;
  bool _sending = false;
  late int _count = widget.commentCount;

  /// Caption của video (đã trim) — ghim làm bình luận tác giả nếu có.
  String get _authorCaption => widget.video?.caption?.trim() ?? '';

  /// Tên tác giả: ưu tiên tên người đăng (không phải tên shop) cho hợp ngữ
  /// cảnh badge "Tác giả".
  String get _authorName {
    final v = widget.video;
    final n = v?.userName?.trim();
    return (n != null && n.isNotEmpty) ? n : (v?.displayName ?? 'Tác giả');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _repo.fetchComments(widget.videoId, limit: 50);
      if (mounted) setState(() => _comments = list);
    } catch (_) {
      // keep empty
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Chèn [emoji] vào ô nhập tại vị trí con trỏ (giống Shopee Video: chạm
  /// emoji là thêm vào bình luận đang soạn, không gửi ngay).
  void _insertEmoji(String emoji) {
    final sel = _controller.selection;
    final text = _controller.text;
    if (sel.isValid && sel.start >= 0) {
      final newText = text.replaceRange(sel.start, sel.end, emoji);
      _controller.value = _controller.value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + emoji.length),
      );
    } else {
      _controller.text = text + emoji;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    if (!AuthService.instance.isSignedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đăng nhập để bình luận')));
      return;
    }
    setState(() => _sending = true);
    try {
      final c = await _repo.addComment(widget.videoId, text);
      if (!mounted) return;
      setState(() {
        _comments.insert(0, c);
        _count += 1;
        _controller.clear();
        _sending = false;
      });
      widget.onAdded?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AuthService.errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSizes.radiusXl),
        ),
      ),
      child: Column(
        children: [
          // Grabber + header.
          const SizedBox(height: AppSizes.sm),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSizes.md),
            child: Text(
              '$_count bình luận',
              style: const TextStyle(
                fontSize: AppSizes.fontMd,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Divider(height: 1),
          // Caption của video = bình luận đầu tiên của tác giả (ghim ở trên,
          // không tính vào số đếm bình luận).
          if (_authorCaption.isNotEmpty) ...[
            _AuthorCaptionRow(
              name: _authorName,
              avatarUrl: widget.video?.avatarUrl,
              caption: _authorCaption,
              createdAt: widget.video?.createdAt,
            ),
            const Divider(height: 1),
          ],
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _comments.isEmpty
                ? const Center(
                    child: Text(
                      'Hãy là người đầu tiên bình luận về video này',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
                    itemCount: _comments.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (_, i) => _CommentRow(comment: _comments[i]),
                  ),
          ),
          // Hàng emoji phản ứng nhanh + input bar.
          SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _EmojiQuickRow(onTap: _insertEmoji),
                Padding(
              padding: EdgeInsets.fromLTRB(
                AppSizes.md,
                AppSizes.sm,
                AppSizes.sm,
                AppSizes.sm + bottomInset,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Thêm bình luận...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.md,
                          vertical: AppSizes.sm,
                        ),
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppSizes.radiusFull,
                          ),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : const Icon(Icons.send, color: AppColors.primary),
                  ),
                ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hàng emoji phản ứng nhanh phía trên ô nhập (😍 👍 🔥 ...). Chạm 1 emoji là
/// chèn vào bình luận đang soạn — mô phỏng Shopee Video / TikTok.
class _EmojiQuickRow extends StatelessWidget {
  final ValueChanged<String> onTap;
  const _EmojiQuickRow({required this.onTap});

  static const _emojis = ['😍', '👍', '🔥', '🙏', '💖', '😘', '😄', '👌'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final e in _emojis)
            InkResponse(
              onTap: () => onTap(e),
              radius: 24,
              child: Text(e, style: const TextStyle(fontSize: 26)),
            ),
        ],
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  final VideoComment comment;
  const _CommentRow({required this.comment});

  @override
  Widget build(BuildContext context) {
    final avatar = comment.avatarUrl;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primaryContainer,
            backgroundImage: avatar != null
                ? CachedNetworkImageProvider(avatar)
                : null,
            child: avatar == null
                ? const Icon(Icons.person, color: AppColors.primary, size: 20)
                : null,
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      comment.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: AppSizes.fontSm,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    Text(
                      _relative(comment.createdAt),
                      style: const TextStyle(
                        fontSize: AppSizes.fontXs,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  comment.content,
                  style: const TextStyle(fontSize: AppSizes.fontMd),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Caption của video hiển thị như bình luận đầu tiên của tác giả: ghim ở đầu
/// danh sách, kèm badge "Tác giả" + thời gian đăng. Mô phỏng Shopee Video.
class _AuthorCaptionRow extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final String caption;
  final DateTime? createdAt;

  const _AuthorCaptionRow({
    required this.name,
    required this.caption,
    this.avatarUrl,
    this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primaryContainer,
            backgroundImage: avatarUrl != null
                ? CachedNetworkImageProvider(avatarUrl!)
                : null,
            child: avatarUrl == null
                ? const Icon(Icons.person, color: AppColors.primary, size: 20)
                : null,
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: AppSizes.fontSm,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSizes.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                      ),
                      child: const Text(
                        'Tác giả',
                        style: TextStyle(
                          fontSize: AppSizes.fontXs,
                          fontWeight: FontWeight.w600,
                          color: AppColors.secondary,
                        ),
                      ),
                    ),
                    if (createdAt != null) ...[
                      const SizedBox(width: AppSizes.sm),
                      Text(
                        _relative(createdAt!),
                        style: const TextStyle(
                          fontSize: AppSizes.fontXs,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                _CaptionText(caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hiển thị caption và tô màu xanh cho mọi #hashtag (giống ô soạn mô tả).
class _CaptionText extends StatelessWidget {
  final String text;
  const _CaptionText(this.text);

  static final RegExp _tag = RegExp(r'#[\p{L}\p{N}_]+', unicode: true);

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in _tag.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      spans.add(
        TextSpan(
          text: m.group(0),
          style: const TextStyle(color: Color(0xFF2B5CB8)),
        ),
      );
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: AppSizes.fontMd,
          color: AppColors.textPrimary,
        ),
        children: spans,
      ),
    );
  }
}

String _relative(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'vừa xong';
  if (d.inMinutes < 60) return '${d.inMinutes} phút';
  if (d.inHours < 24) return '${d.inHours} giờ';
  if (d.inDays < 7) return '${d.inDays} ngày';
  return '${(d.inDays / 7).floor()} tuần';
}
