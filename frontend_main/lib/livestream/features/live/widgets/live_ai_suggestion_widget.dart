// =============================================================================
// live_ai_suggestion_widget.dart
// =============================================================================
// Widget hiển thị các chip câu hỏi gợi ý AI phía trên ô comment.
//
// UI:
//   [Gợi ý: ] [Còn size M không?] [Ship mấy ngày?] [Có COD không?]
//             ─────────────────────────────────────────────────────
//             → user tap chip → câu hỏi điền vào TextEditingController
//             → user có thể sửa trước khi gửi
//
// ANIMATION: chips slide in từ dưới khi load xong.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/livestream/core/utils/logger.dart';

class LiveAiSuggestionWidget extends StatefulWidget {
  /// Danh sách câu hỏi gợi ý (tối đa 3)
  final List<String> suggestions;

  /// Đang loading không (hiện shimmer)
  final bool isLoading;

  /// Callback khi user tap một chip
  final ValueChanged<String> onSuggestionTapped;

  const LiveAiSuggestionWidget({
    super.key,
    required this.suggestions,
    required this.isLoading,
    required this.onSuggestionTapped,
  });

  @override
  State<LiveAiSuggestionWidget> createState() =>
      _LiveAiSuggestionWidgetState();
}

class _LiveAiSuggestionWidgetState extends State<LiveAiSuggestionWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnim;
  // Cache nội dung để tránh rebuild khi provider notify với cùng suggestions
  List<String> _cachedSuggestions = [];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    if (widget.suggestions.isNotEmpty) {
      _cachedSuggestions = List.from(widget.suggestions);
      _animController.forward();
    }
  }

  bool _suggestionsChanged(List<String> next) {
    if (next.length != _cachedSuggestions.length) return true;
    for (int i = 0; i < next.length; i++) {
      if (next[i] != _cachedSuggestions[i]) return true;
    }
    return false;
  }

  @override
  void didUpdateWidget(LiveAiSuggestionWidget old) {
    super.didUpdateWidget(old);
    if (_suggestionsChanged(widget.suggestions) && widget.suggestions.isNotEmpty) {
      _cachedSuggestions = List.from(widget.suggestions);
      _animController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Luôn hiện chip cũ khi đang load lại — không dùng shimmer khi đã có data
    final showShimmer = widget.isLoading && _cachedSuggestions.isEmpty;
    if (showShimmer) return _buildShimmer();
    if (_cachedSuggestions.isEmpty) return const SizedBox.shrink();

    return SlideTransition(
      position: _slideAnim,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            const Text(
              'Gợi ý:',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _cachedSuggestions
                      .take(3)
                      .map((s) => _SuggestionChip(
                            text: s,
                            onTap: () {
                              AppLogger.logUserEvent(
                                action: 'ai_suggestion_tapped',
                                context: 'LiveAiSuggestionWidget',
                                metadata: {'suggestion': s},
                              );
                              widget.onSuggestionTapped(s);
                            },
                          ))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmer() => Container(
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Row(
      children: List.generate(
        3,
        (_) => Container(
          margin: const EdgeInsets.only(right: 6),
          width: 90,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(30),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ),
  );
}

class _SuggestionChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _SuggestionChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(30),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withAlpha(60), width: 0.8),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
