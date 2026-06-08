// =============================================================================
// live_chat_widget.dart
// =============================================================================
// Widget chat overlay trong màn hình livestream.
//
// THIẾT KẾ (giống Shopee Live thực tế):
//   - Mỗi dòng: [avatar 20px] [bubble: tên in đậm + nội dung cùng dòng]
//   - Bubble: nền đen 50% trong suốt, bo góc 12px
//   - Font: 12sp — nhỏ, đọc được, không che video quá nhiều
//   - Tên: màu theo role (host=vàng, currentUser=xanh lá, other=trắng70%)
//   - Không có border, không padding thừa — tối giản như Shopee
//   - Bot message: nền indigo đậm, có icon 🤖, mono font
//   - Max 3 dòng mỗi bubble, auto-scroll xuống khi có comment mới
//
// PHÂN LOẠI MÀU:
//   Host      → tên vàng  (#FFD700), nền nâu vàng 60%
//   CurrentUser → tên xanh mint, nền primary 55%
//   Bot       → nền indigo 82%, chữ lavender
//   Other     → tên trắng 70%, nền đen 50%
// =============================================================================

import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/models/live_stream_model.dart';

class LiveChatWidget extends StatefulWidget {
  final List<LiveComment> comments;

  /// Chiều cao tối đa vùng chat (px)
  final double maxHeight;

  const LiveChatWidget({
    super.key,
    required this.comments,
    this.maxHeight = 180,
  });

  @override
  State<LiveChatWidget> createState() => _LiveChatWidgetState();
}

class _LiveChatWidgetState extends State<LiveChatWidget> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LiveChatWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.comments.length != oldWidget.comments.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: AppDurations.commentScroll,
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.comments.isEmpty) {
      // Soft placeholder so the chat area isn't blank — both host and
      // viewer see "Chưa có tin nhắn nào" until somebody types.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.sm),
        child: Text(
          'Chưa có tin nhắn nào',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: AppSizes.fontSm,
            shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
          ),
        ),
      );
    }

    return SizedBox(
      height: widget.maxHeight,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.sm,
          vertical: AppSizes.xs,
        ),
        itemCount: widget.comments.length,
        itemBuilder: (_, i) => _CommentRow(comment: widget.comments[i]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Comment row
// ─────────────────────────────────────────────────────────────────────────────

class _CommentRow extends StatelessWidget {
  final LiveComment comment;

  const _CommentRow({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Khoảng cách giữa các dòng — 4px như Shopee (không phải 8px)
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _Avatar(comment: comment),
          const SizedBox(width: 5),
          Flexible(child: _Bubble(comment: comment)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Avatar — 20px, đủ nhỏ để không lấn không gian
// ─────────────────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final LiveComment comment;

  const _Avatar({required this.comment});

  @override
  Widget build(BuildContext context) {
    final isHost = comment.isHost;
    final isBot = comment.isBotMessage;

    if (isBot) {
      // Bot: icon robot thay avatar
      return Container(
        width: 20,
        height: 20,
        decoration: const BoxDecoration(
          color: Color(0xFF283593),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Text('🤖', style: TextStyle(fontSize: 11)),
        ),
      );
    }

    return CircleAvatar(
      radius: 10,
      backgroundColor: isHost
          ? const Color(0xFFB8860B).withValues(alpha: 0.5)
          : Colors.white.withValues(alpha: 0.15),
      child: comment.avatarUrl != null
          ? ClipOval(
              child: Image.network(
                comment.avatarUrl!,
                width: 20,
                height: 20,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _initial(comment, isHost),
              ),
            )
          : _initial(comment, isHost),
    );
  }

  Widget _initial(LiveComment c, bool isHost) {
    return Text(
      c.username.isNotEmpty ? c.username[0].toUpperCase() : '?',
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: isHost ? AppColors.gold : Colors.white70,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bubble — inline: "Tên  nội dung"
// ─────────────────────────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  final LiveComment comment;

  const _Bubble({required this.comment});

  @override
  Widget build(BuildContext context) {
    if (comment.isBotMessage) return _buildBotBubble();
    return _buildUserBubble();
  }

  // ── Bot bubble ──────────────────────────────────────────────────────────

  Widget _buildBotBubble() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        // Indigo đậm, đủ tương phản với nền video
        color: const Color(0xFF1A237E).withAlpha(215),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(2),
          topRight: Radius.circular(12),
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        border: Border.all(
          color: const Color(0xFF3F51B5).withAlpha(120),
          width: 0.5,
        ),
      ),
      child: Text(
        comment.message,
        style: const TextStyle(
          // Lavender nhạt, dễ đọc trên nền indigo
          color: Color(0xFFE8EAF6),
          fontSize: 11.5,
          height: 1.45,
          letterSpacing: 0.1,
        ),
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  // ── Regular user bubble ─────────────────────────────────────────────────

  Widget _buildUserBubble() {
    // Nền đủ tối để chữ trắng luôn đọc được dù video sáng hay tối
    Color bgColor;
    if (comment.isCurrentUser) {
      bgColor = AppColors.primary.withValues(alpha: 0.90);
    } else if (comment.isHost) {
      bgColor = const Color(0xFFB8860B).withValues(alpha: 0.90);
    } else {
      bgColor = Colors.black.withValues(alpha: 0.75);
    }

    // Màu tên
    Color nameColor;
    if (comment.isCurrentUser) {
      nameColor = const Color(0xFFA5D6A7); // xanh lá nhạt
    } else if (comment.isHost) {
      nameColor = AppColors.gold;
    } else if (comment.nameColor != null) {
      nameColor = _hex(comment.nameColor!) ?? Colors.white70;
    } else {
      nameColor = const Color(0xFFE0E0E0);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(2),
          topRight: Radius.circular(12),
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: RichText(
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: [
            // Tên in đậm
            TextSpan(
              text: comment.username,
              style: TextStyle(
                color: nameColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.4,
                shadows: const [Shadow(color: Colors.black, blurRadius: 6), Shadow(color: Colors.black, blurRadius: 2)],
              ),
            ),
            // Badge Host
            if (comment.isHost)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  margin: const EdgeInsets.only(left: 3, right: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Text(
                    'Host',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            // Khoảng cách nhỏ giữa tên và nội dung
            const TextSpan(text: '  '),
            // Nội dung
            TextSpan(
              text: comment.message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                height: 1.4,
                shadows: [Shadow(color: Colors.black, blurRadius: 6), Shadow(color: Colors.black, blurRadius: 2)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color? _hex(String hex) {
    try {
      final h = hex.replaceAll('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return null;
    }
  }
}
