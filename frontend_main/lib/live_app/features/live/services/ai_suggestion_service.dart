// =============================================================================
// ai_suggestion_service.dart
// Gọi backend DeepSeek API để lấy câu hỏi gợi ý cho người xem livestream.
// API key DeepSeek chỉ nằm trên server (DEEPSEEK_API_KEY env), không có trong app.
// =============================================================================

import 'dart:async';
import 'dart:math';
import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/core/utils/logger.dart';

const _tag = 'AiSuggestionService';

class AiSuggestionService {
  AiSuggestionService._();
  static final instance = AiSuggestionService._();

  Timer? _refreshTimer;

  Future<List<String>> getSuggestions({
    required String streamId,
    required String currentProductName,
    required String currentProductCategory,
    List<String> recentComments = const [],
  }) async {
    AppLogger.logInfo(_tag, 'Fetching AI suggestions for "$currentProductName"');

    try {
      final suggestions = await _fetchFromApi(
        streamId:    streamId,
        productName: currentProductName,
        category:    currentProductCategory,
        recentComments: recentComments,
      );

      AppLogger.logUserEvent(
        action: 'ai_suggestions_loaded',
        context: _tag,
        metadata: {
          'streamId': streamId,
          'product': currentProductName,
          'count': suggestions.length,
        },
      );

      return suggestions;
    } catch (e, st) {
      AppLogger.logError(_tag, 'AI suggestions failed, using fallback', e, st);
      return _fallbackSuggestions(currentProductCategory);
    }
  }

  void dispose() {
    _refreshTimer?.cancel();
  }

  // ─── Real API ─────────────────────────────────────────────────────────────

  Future<List<String>> _fetchFromApi({
    required String streamId,
    required String productName,
    required String category,
    required List<String> recentComments,
  }) async {
    final dio = AuthService.instance.authorizedDio();
    final response = await dio.post(
      '/api/live/streams/$streamId/ai-suggestions',
      data: {
        'product_name':     productName,
        'category':         category,
        'recent_comments':  recentComments.take(10).toList(),
      },
    );
    final List list = response.data['suggestions'] as List;
    return list.cast<String>();
  }

  // ─── Fallback (dùng khi API lỗi) ─────────────────────────────────────────

  static const _categoryQuestions = <String, List<String>>{
    'Tã bỉm': [
      'Size M phù hợp bé mấy kg vậy shop?',
      'Tã có chống hăm không ạ?',
      'Mua 2 gói có giảm thêm không shop?',
    ],
    'Sữa bột': [
      'Sữa phù hợp bé mấy tháng tuổi?',
      'Hạn sử dụng còn bao lâu shop ơi?',
      'Combo mua 2 hộp giá bao nhiêu?',
    ],
    'Thực phẩm': [
      'Hàng có chứng nhận an toàn thực phẩm không shop?',
      'Bảo quản bao lâu sau khi mở?',
      'Nguồn gốc từ đâu vậy shop?',
    ],
    'Giày thể thao': [
      'Size 42 còn không shop?',
      'Đế có chống trượt không ạ?',
      'Đổi trả trong bao lâu nếu không vừa?',
    ],
    'Trang điểm': [
      'Tone da ngăm dùng màu nào phù hợp?',
      'SPF bao nhiêu vậy shop?',
      'Da nhạy cảm dùng được không ạ?',
    ],
    'Dưỡng da': [
      'Dùng sáng hay tối vậy shop?',
      'Da dầu dùng có bị nhờn không?',
      'Một chai dùng được bao lâu?',
    ],
    'Rau lá': [
      'Rau có phun thuốc không shop?',
      'Đặt sáng giao chiều được không?',
      'Mua 3 bó giảm không shop?',
    ],
  };

  static const _genericQuestions = [
    'Phí ship bao nhiêu vậy shop?',
    'Đổi trả như thế nào nếu hàng lỗi?',
    'Có COD không shop ơi?',
    'Mua lần đầu có voucher không?',
    'Giao trong ngày được không ạ?',
  ];

  List<String> _fallbackSuggestions(String category) {
    final pool = _categoryQuestions[category] ?? _genericQuestions;
    final all  = [...pool, ..._genericQuestions];
    final rng  = Random(DateTime.now().millisecondsSinceEpoch);
    all.shuffle(rng);
    return all.take(3).toList();
  }
}
