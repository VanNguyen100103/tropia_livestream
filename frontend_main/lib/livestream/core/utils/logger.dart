// =============================================================================
// logger.dart
// =============================================================================
// Tiện ích ghi log tập trung cho toàn bộ ứng dụng Tropia.
//
// Sử dụng package `logger` (https://pub.dev/packages/logger) làm nền tảng,
// và bọc thêm:
//   - Timestamp tự động cho mỗi log entry
//   - Tag theo tính năng (module tag) để lọc log dễ hơn
//   - Các phương thức tiện lợi: logInfo, logWarning, logError, logDebug
//
// CÁCH SỬ DỤNG:
//   // Khởi tạo (thực hiện 1 lần trong main.dart)
//   AppLogger.init();
//
//   // Ghi log ở bất kỳ đâu trong app
//   AppLogger.logInfo('LiveProvider', 'Stream opened: ${stream.id}');
//   AppLogger.logError('LiveProvider', 'Failed to load streams', error);
//   AppLogger.logDebug('LiveStreamScreen', 'User tapped like button');
//
// CHÚ Ý: Trong production (release build), logger tự động tắt output
//         nhờ kAssertionsEnabled / kDebugMode check.
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Custom log printer với timestamp & tag
// ─────────────────────────────────────────────────────────────────────────────

/// Custom [LogPrinter] bổ sung timestamp và tag vào mỗi dòng log.
///
/// Format output:
///   [HH:mm:ss.SSS] [TAG] MESSAGE
///   (error stack trace nếu có)
class _TropiaLogPrinter extends LogPrinter {
  final String tag;

  _TropiaLogPrinter(this.tag);

  @override
  List<String> log(LogEvent event) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';

    final levelStr = _levelLabel(event.level);
    final message = event.message;
    final lines = <String>['[$timeStr] $levelStr [$tag] $message'];

    // Thêm error object nếu có
    if (event.error != null) {
      lines.add('  ↳ ERROR: ${event.error}');
    }

    // Thêm stack trace nếu có (chỉ 8 dòng đầu để tránh quá dài)
    if (event.stackTrace != null) {
      final stackLines = event.stackTrace.toString().split('\n');
      final limit = stackLines.length > 8 ? 8 : stackLines.length;
      for (int i = 0; i < limit; i++) {
        if (stackLines[i].trim().isNotEmpty) {
          lines.add('  │ ${stackLines[i]}');
        }
      }
    }

    return lines;
  }

  /// Chuyển [Level] sang chuỗi có màu ANSI (chỉ hoạt động trên terminal hỗ trợ ANSI).
  String _levelLabel(Level level) {
    switch (level) {
      case Level.debug:
        return '\x1B[34m[DEBUG]\x1B[0m'; // blue
      case Level.info:
        return '\x1B[32m[INFO ]\x1B[0m'; // green
      case Level.warning:
        return '\x1B[33m[WARN ]\x1B[0m'; // yellow
      case Level.error:
        return '\x1B[31m[ERROR]\x1B[0m'; // red
      case Level.fatal:
        return '\x1B[35m[FATAL]\x1B[0m'; // magenta
      default:
        return '[LOG  ]';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppLogger – API công khai
// ─────────────────────────────────────────────────────────────────────────────

/// Singleton logger cho ứng dụng Tropia.
///
/// Gọi [AppLogger.init()] một lần trong [main()] trước khi dùng.
class AppLogger {
  AppLogger._(); // private constructor – không cho phép khởi tạo trực tiếp

  static Logger? _logger;

  /// Khởi tạo logger.
  ///
  /// Tham số:
  ///   [level]: Mức log tối thiểu sẽ được ghi ra (mặc định: [Level.debug])
  ///   [enableInRelease]: Có ghi log trong release build không (mặc định: false)
  static void init({
    Level level = Level.debug,
    bool enableInRelease = false,
  }) {
    // Trong release build, chỉ ghi log nếu enableInRelease = true
    if (!kDebugMode && !enableInRelease) {
      // Tạo logger với filter loại bỏ tất cả log
      _logger = Logger(
        filter: _SilentFilter(),
        printer: PrettyPrinter(),
      );
      return;
    }

    _logger = Logger(
      filter: ProductionFilter(),
      printer: _TropiaLogPrinter('Tropia'),
      level: level,
    );

    // Ghi log khởi động
    _logger!.i('AppLogger initialized. Mode: ${kDebugMode ? "DEBUG" : "RELEASE"}');
  }

  // ─── Các phương thức log công khai ───────────────────────────────────────

  /// Ghi log mức DEBUG – dùng cho thông tin phát triển, tracing chi tiết.
  ///
  /// Ví dụ: `AppLogger.logDebug('LiveStreamScreen', 'Rendering comment list');`
  static void logDebug(String tag, String message) {
    _ensureInitialized();
    _logger!.d('[$tag] $message');
  }

  /// Ghi log mức INFO – sự kiện bình thường quan trọng.
  ///
  /// Ví dụ: `AppLogger.logInfo('LiveProvider', 'Stream #123 opened by user');`
  static void logInfo(String tag, String message) {
    _ensureInitialized();
    _logger!.i('[$tag] $message');
  }

  /// Ghi log mức WARNING – tình huống bất thường nhưng không gây crash.
  ///
  /// Ví dụ: `AppLogger.logWarning('VideoPlayer', 'Buffer underrun, buffering...');`
  static void logWarning(String tag, String message) {
    _ensureInitialized();
    _logger!.w('[$tag] $message');
  }

  /// Ghi log mức ERROR – lỗi xảy ra, cần điều tra.
  ///
  /// Tham số:
  ///   [error]: Exception hoặc object lỗi (tùy chọn)
  ///   [stackTrace]: Stack trace (tùy chọn, tự động lấy nếu là Exception)
  ///
  /// Ví dụ:
  /// ```dart
  /// try {
  ///   await loadStreams();
  /// } catch (e, st) {
  ///   AppLogger.logError('LiveProvider', 'Failed to load streams', e, st);
  /// }
  /// ```
  static void logError(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    _ensureInitialized();
    _logger!.e('[$tag] $message', error: error, stackTrace: stackTrace);
  }

  /// Ghi log mức FATAL – lỗi nghiêm trọng, app có thể crash.
  static void logFatal(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    _ensureInitialized();
    _logger!.f('[$tag] $message', error: error, stackTrace: stackTrace);
  }

  // ─── Log helper cho các sự kiện người dùng ───────────────────────────────

  /// Ghi log sự kiện tương tác người dùng (analytics-ready).
  ///
  /// Dùng cho: like, share, comment, follow, buy, v.v.
  ///
  /// Format: `[USER_EVENT] action | context | metadata`
  static void logUserEvent({
    required String action,
    required String context,
    Map<String, dynamic>? metadata,
  }) {
    _ensureInitialized();
    final meta = metadata != null ? ' | ${metadata.toString()}' : '';
    _logger!.i('[USER_EVENT] $action | $context$meta');
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  /// Đảm bảo logger đã được khởi tạo. Nếu chưa, tự khởi tạo với config mặc định.
  static void _ensureInitialized() {
    if (_logger == null) {
      init(); // tự khởi tạo nếu dev quên gọi init()
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SilentFilter – tắt tất cả log trong release
// ─────────────────────────────────────────────────────────────────────────────

/// Filter loại bỏ tất cả log – dùng trong release build.
class _SilentFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) => false;
}
